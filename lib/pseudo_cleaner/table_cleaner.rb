module PseudoCleaner
  class TableCleaner
    attr_accessor :table

    @@initial_states = {}

    def self.reset_suite
      @@initial_states = {}
    end

    def initialize(start_method, end_method, table, options = {})
      raise "You must specify a table object." unless table
      unless PseudoCleaner::MasterCleaner::VALID_START_METHODS.include?(start_method)
        raise "You must specify a valid start function from: #{PseudoCleaner::MasterCleaner::VALID_START_METHODS}."
      end
      unless PseudoCleaner::MasterCleaner::VALID_END_METHODS.include?(end_method)
        raise "You must specify a valid end function from: #{PseudoCleaner::MasterCleaner::VALID_END_METHODS}."
      end

      @table = table

      @@initial_states[@table] ||= {}
      initial_state            = @@initial_states[@table]

      @options = options

      @options[:table_start_method] ||= start_method
      @options[:table_end_method]   ||= end_method
      @options[:output_diagnostics] ||= PseudoCleaner::Configuration.current_instance.output_diagnostics

      unless initial_state.has_key?(:table_is_active_record)
        initial_state[:table_is_active_record] = false

        if Object.const_defined?("ActiveRecord", false) && ActiveRecord.const_defined?("Base", false)
          if table.is_a?(String) || table.is_a?(Symbol)
            initial_state[:table_is_active_record] = true
            initial_state[:table_name]             = table
          else
            table_super_class = table.superclass

            while !initial_state[:table_is_active_record] && table_super_class
              initial_state[:table_is_active_record] = (table_super_class == ActiveRecord::Base)
              initial_state[:table_name]             = table.name if initial_state[:table_is_active_record]
              table_super_class                      = table_super_class.superclass
            end
          end
        end
      end

      unless initial_state.has_key?(:table_is_sequel_model)
        initial_state[:table_is_sequel_model] = false

        if Object.const_defined?("Sequel", false) && Sequel.const_defined?("Model", false)
          if table.is_a?(String) || table.is_a?(Symbol)
            initial_state[:table_is_sequel_model] = Sequel::DATABASES[0][table]
            initial_state[:table_name]            = table
          else
            table_super_class = table.superclass

            while !initial_state[:table_is_sequel_model] && table_super_class
              initial_state[:table_is_sequel_model] = (table_super_class == Sequel::Model)
              initial_state[:table_name]            = table.name if initial_state[:table_is_sequel_model]
              table_super_class                     = table_super_class.superclass
            end
          end
        end
      end
    end

    def test_start test_strategy
      @test_strategy = test_strategy
      save_state
    end

    def suite_start test_strategy
      @test_strategy = test_strategy
      save_state
    end

    def save_state
      initial_state = @@initial_states[@table]

      if @test_strategy == :pseudo_delete && !initial_state[:saved]
        initial_state[:saved] = true

        if @options[:output_diagnostics]
          PseudoCleaner::Logger.write("  Gathering information about \"#{initial_state[:table_name]}\"...".blue.on_light_white)
        end

        if initial_state[:table_is_active_record]
          test_start_active_record @test_strategy
        end

        if initial_state[:table_is_sequel_model]
          test_start_sequel_model @test_strategy
        end

        reset_auto_increment !PseudoCleaner::Configuration.current_instance.clean_database_before_tests

        if initial_state.has_key?(:count) && @options[:output_diagnostics]
          PseudoCleaner::Logger.write("    *** There are no columns to track inserts and updates easily on for #{initial_state[:table_name]} ***".red.on_light_white)
        end
      end
    end

    def test_start_active_record test_strategy
      initial_state = @@initial_states[@table]

      if table.is_a?(String) || table.is_a?(Symbol)
        # TODO: do this
        raise "This isn't done yet"
      else
        if columns.find { |column| column.name == "id" }
          initial_state[:max_id] = table.maximum(:id) || 0
          PseudoCleaner::Logger.write("    max(id) = #{initial_state[:max_id]}") if @options[:output_diagnostics]
        end

        [:created, :updated].each do |date_name|
          [:at, :on].each do |verb_name|
            date_column_name = "#{date_name}_#{verb_name}"

            if columns.find { |column| column.name == date_column_name }
              initial_state[date_name] = {
                  column_name: date_column_name,
                  value:       table.maximum(date_column_name) || Time.now - 1.second
              }
              if @options[:output_diagnostics]
                PseudoCleaner::Logger.write("    max(#{initial_state[date_name][:column_name]}) = #{initial_state[date_name][:value]}")
              end

              break
            end
          end
        end
      end

      if initial_state.blank?
        # TODO: do this
        raise "this isn't done yet"

        # initial_state[:count] = access_table.count
      end
    end

    def test_start_sequel_model test_strategy
      initial_state = @@initial_states[@table]
      access_table  = sequel_model_table

      if access_table.columns.include?(:id)
        initial_state[:max_id] = access_table.unfiltered.max(:id) || 0
        PseudoCleaner::Logger.write("    max(id) = #{initial_state[:max_id]}") if @options[:output_diagnostics]
      end

      [:created, :updated].each do |date_name|
        [:at, :on].each do |verb_name|
          date_column_name = "#{date_name}_#{verb_name}".to_sym

          if access_table.columns.include?(date_column_name)
            initial_state[date_name] = {
                column_name: date_column_name,
                value:       access_table.unfiltered.max(date_column_name) || Time.now - 1.second
            }
            if @options[:output_diagnostics]
              PseudoCleaner::Logger.write("    max(#{initial_state[date_name][:column_name]}) = #{initial_state[date_name][:value]}")
            end

            break
          end
        end
      end

      if initial_state.blank?
        initial_state[:count] = access_table.unfiltered.count
      end
    end

    def test_end test_strategy
      reset_table test_strategy, false
    end

    def suite_end test_strategy
      reset_table test_strategy, true
    end

    def reset_table test_strategy, suite_end
      if @test_strategy != test_strategy
        if @options[:output_diagnostics]
          PseudoCleaner::Logger.write("  *** The ending strategy for \"#{initial_state[:table_name]}\" changed! ***".red.on_light_white)
        end
      end

      initial_state = @@initial_states[@table]

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
        PseudoCleaner::Logger.write("  Resetting table \"#{initial_state[:table_name]}\"...") if @options[:output_diagnostics]

        if initial_state[:table_is_active_record]
          test_end_active_record test_strategy
        end

        if initial_state[:table_is_sequel_model]
          test_end_sequel_model test_strategy
        end
      end
    end

    def test_end_active_record test_strategy
      initial_state = @@initial_states[@table]
      cleaned_table = false

      if table.is_a?(String) || table.is_a?(Symbol)
        # TODO: do this
        raise "This isn't done yet"
      else
        if initial_state[:max_id]
          the_max     = initial_state[:max_id] || 0
          num_deleted = table.delete_all(["id > :id", id: the_max])
          if num_deleted > 0
            cleaned_table = true

            if @options[:output_diagnostics]
              PseudoCleaner::Logger.write("    Deleted #{num_deleted} records by ID.")
            end
          end
        end

        if initial_state[:created]
          num_deleted = table.
              delete_all(["#{initial_state[:created][:column_name]} > :column_value",
                          column_value: initial_state[:created][:value]])
          if num_deleted > 0
            cleaned_table = true

            if @options[:output_diagnostics]
              PseudoCleaner::Logger.write("    Deleted #{num_deleted} records by #{initial_state[:created][:column_name]}.")
            end
          end
        end

        if initial_state[:updated]
          dirty_count = table.
              where("#{initial_state[:updated][:column_name]} > :column_value",
                    column_value: initial_state[:updated][:value]).count

          if @options[:output_diagnostics] && dirty_count > 0
            # cleaned_table = true

            if @options[:output_diagnostics]
              PseudoCleaner::Logger.write("    *** There are #{dirty_count} records which have been updated and may be dirty remaining after cleaning \"#{initial_state[:table_name]}\"... ***".red.on_light_white)
            end
          end
        end
      end

      if initial_state[:count]
        # TODO: do this
        raise "This isn't done yet"

        # final_count = access_table.unfiltered.count
        # if initial_state[:count] == 0
        #   DatabaseCleaner.clean_with(:truncation, only: [initial_state[:table_name]])
        #   if @options[:output_diagnostics]
        #     PseudoCleaner::Logger.write("    Deleted #{final_count} records by cleaning the table.") if final_count > 0
        #   end
        #
        #   final_count = access_table.unfiltered.count
        # end
        #
        # if initial_state[:count] != final_count
        #   PseudoCleaner::Logger.write("    *** There are #{final_count - initial_state[:count]} dirty records remaining after cleaning \"#{initial_state[:table_name]}\"... ***".red.on_light_white)
        # end
      end

      #TODO:  Add referential integrity checks

      if cleaned_table
        reset_auto_increment true
      end
    end

    def test_end_sequel_model test_strategy
      initial_state = @@initial_states[@table]
      access_table  = sequel_model_table
      cleaned_table = false

      if initial_state[:max_id]
        the_max     = initial_state[:max_id] || 0
        num_deleted = access_table.unfiltered.where { id > the_max }.delete
        if num_deleted > 0
          cleaned_table = true

          if @options[:output_diagnostics]
            PseudoCleaner::Logger.write("    Deleted #{num_deleted} records by ID.")
          end
        end
      end

      if initial_state[:created]
        num_deleted = access_table.
            unfiltered.
            where("`#{initial_state[:created][:column_name]}` > ?", initial_state[:created][:value]).
            delete
        if num_deleted > 0
          cleaned_table = true

          if @options[:output_diagnostics]
            PseudoCleaner::Logger.write("    Deleted #{num_deleted} records by #{initial_state[:created][:column_name]}.")
          end
        end
      end

      if initial_state[:updated]
        dirty_count = access_table.
            unfiltered.
            where("`#{initial_state[:updated][:column_name]}` > ?", initial_state[:updated][:value]).
            count

        if @options[:output_diagnostics] && dirty_count > 0
          # cleaned_table = true

          if @options[:output_diagnostics]
            PseudoCleaner::Logger.write("    *** There are #{dirty_count} records which have been updated and may be dirty remaining after cleaning \"#{initial_state[:table_name]}\"... ***".red.on_light_white)
          end
        end
      end

      if initial_state[:count]
        final_count = access_table.unfiltered.count
        if initial_state[:count] == 0
          cleaned_table = true

          DatabaseCleaner.clean_with(:truncation, only: [initial_state[:table_name]])
          if @options[:output_diagnostics]
            PseudoCleaner::Logger.write("    Deleted #{final_count} records by cleaning the table.") if final_count > 0
          end

          final_count = access_table.unfiltered.count
        end

        if initial_state[:count] != final_count
          initial_state[:count] = final_count
          cleaned_table = true

          PseudoCleaner::Logger.write("    *** There are #{final_count - initial_state[:count]} dirty records remaining after cleaning \"#{initial_state[:table_name]}\"... ***".red.on_light_white)
        end
      end

      #TODO:  Add referential integrity checks

      if cleaned_table
        reset_auto_increment true
      end
    end

    def reset_auto_increment test_start
      initial_state = @@initial_states[@table]

      if test_start
        if initial_state[:table_is_active_record]
          reset_auto_increment_active_record
        end

        if initial_state[:table_is_sequel_model]
          reset_auto_increment_sequel_model
        end
      end
    end

    def reset_auto_increment_active_record
      # TODO: do this
      raise "Not implemented yet"
    end

    def reset_auto_increment_sequel_model
      initial_state = @@initial_states[@table]

      if initial_state[:max_id]
        unless sequel_model_table_name.blank?
          access_table_name = sequel_model_table_name
          if @options[:output_diagnostics]
            puts("    ALTER TABLE targeted_email_batches AUTO_INCREMENT = #{initial_state[:max_id] + 1}")
          end

          DB["ALTER TABLE #{sequel_model_table_name} AUTO_INCREMENT = #{initial_state[:max_id] + 1}"].first
        end
      end
    end

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

    def sequel_model_table
      if table.is_a?(String) || table.is_a?(Symbol)
        Sequel::DATABASES[0][table]
      else
        table.dataset
      end
    end

    def sequel_model_table_name
      if table.is_a?(String) || table.is_a?(Symbol)
        "`#{table}`"
      else
        table.simple_table
      end
    end
  end
end