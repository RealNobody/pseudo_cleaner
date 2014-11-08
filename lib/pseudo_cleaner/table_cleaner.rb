module PseudoCleaner
  class TableCleaner
    attr_accessor :table,
                  :table_name

    VALID_START_METHODS = [:test_start, :suite_start]
    VALID_END_METHODS   = [:test_end, :suite_end]
    VALID_TEST_METHODS  = VALID_START_METHODS + VALID_END_METHODS

    class << self
      def cleaner_class(table_name)
        seed_class_name      = "#{table_name.to_s.classify}Cleaner"
        seed_class_base_name = seed_class_name.demodulize
        base_module          = seed_class_name.split("::")[0..-2].join("::")
        base_module_classes  = [Object]

        unless base_module.blank?
          base_module_classes = base_module_classes.unshift base_module.constantize
        end

        return_class = nil
        2.times do
          base_module_classes.each do |base_class|
            if (base_class.const_defined?(seed_class_base_name, false))
              if base_class == Object
                return_class = seed_class_base_name.constantize
              else
                return_class = "#{base_class.name}::#{seed_class_base_name}".constantize
              end

              break
            end
          end

          break if return_class

          seeder_file = "db/cleaners/"
          seeder_file += base_module.split("::").map { |module_name| module_name.underscore }.join("/")
          seeder_file += "/" unless seeder_file[-1] == "/"
          seeder_file += seed_class_base_name.underscore
          seeder_file += ".rb"
          seeder_file = File.join(Rails.root, seeder_file)

          break unless File.exists?(seeder_file)

          require seeder_file
        end

        # unless return_class &&
        #     VALID_TEST_METHODS.any? { |test_method| return_class.instance_methods.include?(test_method.to_sym) }
        #   return_class = table
        # end

        unless return_class &&
            VALID_TEST_METHODS.any? { |test_method| return_class.instance_methods.include?(test_method.to_sym) }
          return_class = PseudoCleaner::TableCleaner
        end

        return_class
      end
    end

    def initialize(start_method, end_method, table, options = {})
      raise "You must specify a table object." unless table
      unless VALID_START_METHODS.include?(start_method)
        raise "You must specify a valid start function from: #{VALID_START_METHODS}."
      end
      unless VALID_END_METHODS.include?(end_method)
        raise "You must specify a valid end function from: #{VALID_END_METHODS}."
      end

      @table   = table
      @options = options

      @options[:table_start_method] ||= start_method
      @options[:table_end_method]   ||= end_method
      @options[:output_diagnostics] ||= PseudoCleaner::Configuration.current_instance.output_diagnostics

      @table_is_active_record = false

      if Object.const_defined?("ActiveRecord", false) && ActiveRecord.const_defined?("Base", false)
        if table.is_a?(String) || table.is_a?(Symbol)
          @table_is_active_record = true
          @table_name             = table
        else
          table_super_class = table.superclass

          while !@table_is_active_record && table_super_class
            @table_is_active_record = (table_super_class == ActiveRecord::Base)
            @table_name             = table.name if @table_is_active_record
            table_super_class       = table_super_class.superclass
          end
        end
      end

      @table_is_sequel_model = false

      if Object.const_defined?("Sequel", false) && Sequel.const_defined?("Model", false)
        if table.is_a?(String) || table.is_a?(Symbol)
          @table_is_sequel_model = Sequel::DATABASES[0][table]
          @table_name            = table
        else
          table_super_class = table.superclass

          while !@table_is_sequel_model && table_super_class
            @table_is_sequel_model = (table_super_class == Sequel::Model)
            @table_name            = table.name if @table_is_sequel_model
            table_super_class      = table_super_class.superclass
          end
        end
      end
    end

    def test_start test_strategy
      @initial_state = {}
      @test_strategy = test_strategy

      if test_strategy == :pseudo_delete
        if @options[:output_diagnostics]
          PseudoCleaner::Logger.write("  Gathering information about \"#{table_name}\"...".blue.on_light_white)
        end

        if @table_is_active_record
          test_start_active_record test_strategy
        end

        if @table_is_sequel_model
          test_start_sequel_model test_strategy
        end

        reset_auto_increment true

        if @initial_state.has_key?(:count) && @options[:output_diagnostics]
          PseudoCleaner::Logger.write("    *** There are no columns to track inserts and updates easily on for #{table_name} ***".red.on_light_white)
        end
      end
    end

    def test_start_active_record test_strategy
      if table.is_a?(String) || table.is_a?(Symbol)
        # TODO: do this
        raise "This isn't done yet"
      else
        if columns.find { |column| column.name == "id" }
          @initial_state[:max_id] = table.maximum(:id) || 0
          PseudoCleaner::Logger.write("    max(id) = #{@initial_state[:max_id]}") if @options[:output_diagnostics]
        end

        [:created, :updated].each do |date_name|
          [:at, :on].each do |verb_name|
            date_column_name = "#{date_name}_#{verb_name}"

            if columns.find { |column| column.name == date_column_name }
              @initial_state[date_name] = {
                  column_name: date_column_name,
                  value:       table.maximum(date_column_name) || Time.now - 1.second
              }
              if @options[:output_diagnostics]
                PseudoCleaner::Logger.write("    max(#{@initial_state[date_name][:column_name]}) = #{@initial_state[date_name][:value]}")
              end

              break
            end
          end
        end
      end

      if @initial_state.blank?
        # TODO: do this
        raise "this isn't done yet"

        # @initial_state[:count] = access_table.count
      end
    end

    def test_start_sequel_model test_strategy
      access_table = sequel_model_table

      if access_table.columns.include?(:id)
        @initial_state[:max_id] = access_table.unfiltered.max(:id) || 0
        PseudoCleaner::Logger.write("    max(id) = #{@initial_state[:max_id]}") if @options[:output_diagnostics]
      end

      [:created, :updated].each do |date_name|
        [:at, :on].each do |verb_name|
          date_column_name = "#{date_name}_#{verb_name}".to_sym

          if access_table.columns.include?(date_column_name)
            @initial_state[date_name] = {
                column_name: date_column_name,
                value:       access_table.unfiltered.max(date_column_name) || Time.now - 1.second
            }
            if @options[:output_diagnostics]
              PseudoCleaner::Logger.write("    max(#{@initial_state[date_name][:column_name]}) = #{@initial_state[date_name][:value]}")
            end

            break
          end
        end
      end

      if @initial_state.blank?
        @initial_state[:count] = access_table.unfiltered.count
      end
    end

    def test_end test_strategy
      if @test_strategy != test_strategy
        if @options[:output_diagnostics]
          PseudoCleaner::Logger.write("  *** The ending strategy for \"#{table_name}\" changed! ***".red.on_light_white)
        end
      end

      if @test_strategy == :pseudo_delete || test_strategy == :pseudo_delete
        # we should check the relationships for any records which still refer to
        # a now deleted record.  (i.e. if we updated a record to refer to a record)
        # we deleted...
        #
        # Which is why this is not a common or particularly good solution.
        #
        # I'm using it because it is faster than reseeding each test...
        # And, I can be responsible for worrying about referential integrity in the test
        # if I want to...
        PseudoCleaner::Logger.write("  Resetting table \"#{table_name}\"...") if @options[:output_diagnostics]

        if @table_is_active_record
          test_end_active_record test_strategy
        end

        if @table_is_sequel_model
          test_end_sequel_model test_strategy
        end

        reset_auto_increment false
      end
    end

    def test_end_active_record test_strategy
      if table.is_a?(String) || table.is_a?(Symbol)
        # TODO: do this
        raise "This isn't done yet"
      else
        if @initial_state[:max_id]
          the_max     = @initial_state[:max_id] || 0
          num_deleted = table.delete_all(["id > :id", id: the_max])
          if @options[:output_diagnostics]
            PseudoCleaner::Logger.write("    Deleted #{num_deleted} records by ID.") if num_deleted > 0
          end
        end

        if @initial_state[:created]
          num_deleted = table.
              delete_all(["#{@initial_state[:created][:column_name]} > :column_value",
                          column_value: @initial_state[:created][:value]])
          if num_deleted > 0
            if @options[:output_diagnostics]
              PseudoCleaner::Logger.write("    Deleted #{num_deleted} records by #{@initial_state[:created][:column_name]}.")
            end
          end
        end

        if @initial_state[:updated]
          dirty_count = table.
              where("#{@initial_state[:updated][:column_name]} > :column_value",
                    column_value: @initial_state[:updated][:value]).count

          if @options[:output_diagnostics] && dirty_count > 0
            if @options[:output_diagnostics]
              PseudoCleaner::Logger.write("    *** There are #{dirty_count} records which have been updated and may be dirty remaining after cleaning \"#{table_name}\"... ***".red.on_light_white)
            end
          end
        end
      end

      if @initial_state[:count]
        # TODO: do this
        raise "This isn't done yet"

        # final_count = access_table.unfiltered.count
        # if @initial_state[:count] == 0
        #   DatabaseCleaner.clean_with(:truncation, only: [@table_name])
        #   if @options[:output_diagnostics]
        #     PseudoCleaner::Logger.write("    Deleted #{final_count} records by cleaning the table.") if final_count > 0
        #   end
        #
        #   final_count = access_table.unfiltered.count
        # end
        #
        # if @initial_state[:count] != final_count
        #   PseudoCleaner::Logger.write("    *** There are #{final_count - @initial_state[:count]} dirty records remaining after cleaning \"#{table_name}\"... ***".red.on_light_white)
        # end
      end

      #TODO:  Add referential integrity checks
    end

    def test_end_sequel_model test_strategy
      access_table = sequel_model_table

      if @initial_state[:max_id]
        the_max     = @initial_state[:max_id] || 0
        num_deleted = access_table.unfiltered.where { id > the_max }.delete
        if @options[:output_diagnostics]
          PseudoCleaner::Logger.write("    Deleted #{num_deleted} records by ID.") if num_deleted > 0
        end
      end

      if @initial_state[:created]
        num_deleted = access_table.
            unfiltered.
            where("`#{@initial_state[:created][:column_name]}` > ?", @initial_state[:created][:value]).
            delete
        if num_deleted > 0
          if @options[:output_diagnostics]
            PseudoCleaner::Logger.write("    Deleted #{num_deleted} records by #{@initial_state[:created][:column_name]}.")
          end
        end
      end

      if @initial_state[:updated]
        dirty_count = access_table.
            unfiltered.
            where("`#{@initial_state[:updated][:column_name]}` > ?", @initial_state[:updated][:value]).
            count

        if @options[:output_diagnostics] && dirty_count > 0
          if @options[:output_diagnostics]
            PseudoCleaner::Logger.write("    *** There are #{dirty_count} records which have been updated and may be dirty remaining after cleaning \"#{table_name}\"... ***".red.on_light_white)
          end
        end
      end

      if @initial_state[:count]
        final_count = access_table.unfiltered.count
        if @initial_state[:count] == 0
          DatabaseCleaner.clean_with(:truncation, only: [@table_name])
          if @options[:output_diagnostics]
            PseudoCleaner::Logger.write("    Deleted #{final_count} records by cleaning the table.") if final_count > 0
          end

          final_count = access_table.unfiltered.count
        end

        if @initial_state[:count] != final_count
          PseudoCleaner::Logger.write("    *** There are #{final_count - @initial_state[:count]} dirty records remaining after cleaning \"#{table_name}\"... ***".red.on_light_white)
        end
      end

      #TODO:  Add referential integrity checks
    end

    def reset_auto_increment test_start
      unless test_start && PseudoCleaner::Configuration.current_instance.clean_database_before_tests
        if @table_is_active_record
          reset_auto_increment_active_record
        end

        if @table_is_sequel_model
          reset_auto_increment_sequel_model
        end
      end
    end

    def reset_auto_increment_active_record
      # TODO: do this
      raise "Not implemented yet"
    end

    def reset_auto_increment_sequel_model
      if @initial_state[:max_id]
        access_table_name = sequel_model_table_name
        DB["ALTER TABLE `#{sequel_model_table_name}` AUTO_INCREMENT = #{@initial_state[:max_id] + 1}"]
      end
    end

    # for the default methods, suite and test start/end are identical.
    # This does not have to be true for all tables, tests, etc.
    alias_method :suite_start, :test_start
    alias_method :suite_end, :test_end

    def <=>(other_object)
      if (other_object.is_a?(PseudoCleaner::TableCleaner))
        return 0 if other_object.table == self.table

        Seedling::Seeder.create_order.each do |create_table|
          if create_table == self.table
            return -1
          elsif create_table == other_object.table
            return 1
          end
        end
      else
        if other_object.respond_to?(:<=>)
          comparison = (other_object <=> self)
          if comparison
            return -1 * comparison
          end
        end
      end

      return -1
    end
  end

  def sequel_model_table
    if table.is_a?(String) || table.is_a?(Symbol)
      Sequel::DATABASES[0][table]
    else
      table.dataset
    end
  end

  def sequel_model_table_name
    if table.is_a?(String) || table.is_a?(Symbol)
      table
    else
      table.name
    end
  end
end