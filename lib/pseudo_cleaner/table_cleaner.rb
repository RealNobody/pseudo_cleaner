module PseudoCleaner
  class TableCleaner
    attr_accessor :table

    @@initial_states = {}

    def reset_suite
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
      @options[:output_diagnostics] ||= PseudoCleaner::Configuration.current_instance.output_diagnostics ||
          PseudoCleaner::Configuration.current_instance.post_transaction_analysis

      unless initial_state.has_key?(:table_is_active_record)
        initial_state[:table_is_active_record] = false

        if Object.const_defined?("ActiveRecord", false) && ActiveRecord.const_defined?("Base", false)
          if symbol_table?
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
          if symbol_table?
            initial_state[:table_is_sequel_model] = PseudoCleaner::Configuration.db_connection(:sequel)[table]
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
      @test_strategy ||= test_strategy
      save_state
    end

    def suite_start test_strategy
      @test_strategy ||= test_strategy
      save_state
    end

    def within_report_block(description, conditional, &block)
      @report_table = nil

      if PseudoCleaner::MasterCleaner.report_table && conditional
        Cornucopia::Util::ReportTable.new(nested_table:         PseudoCleaner::MasterCleaner.report_table,
                                          nested_table_label:   description,
                                          suppress_blank_table: true) do |sub_report|
          @report_table = sub_report

          block.yield
        end
      else
        block.yield
      end

      @report_table = nil
    end

    def save_state
      initial_state = @@initial_states[@table]

      if @test_strategy == :pseudo_delete && !initial_state[:saved]
        initial_state[:saved] = true

        within_report_block(initial_state[:table_name], @options[:output_diagnostics]) do
          if @options[:output_diagnostics]
            PseudoCleaner::MasterCleaner.report_error

            unless @report_table
              PseudoCleaner::Logger.write("  Gathering information about \"#{initial_state[:table_name]}\"...".blue.on_light_white)
            end
          end

          if initial_state[:table_is_active_record]
            test_start_active_record @test_strategy
          end

          if initial_state[:table_is_sequel_model]
            test_start_sequel_model @test_strategy
          end

          if PseudoCleaner::Configuration.current_instance.reset_auto_increment
            reset_auto_increment !PseudoCleaner::Configuration.current_instance.clean_database_before_tests
          end

          if initial_state.has_key?(:count) && @options[:output_diagnostics]
            if @report_table
              @report_table.write_stats "", "*** There are no columns to track inserts and updates easily on for #{initial_state[:table_name]} ***"
            else
              PseudoCleaner::Logger.write("    *** There are no columns to track inserts and updates easily on for #{initial_state[:table_name]} ***".red.on_light_white)
            end
          end
        end
      end
    end

    def symbol_table?
      table.is_a?(String) || table.is_a?(Symbol)
    end

    def active_record_table
      if symbol_table?
        table
      else
        table.table_name
      end
    end

    def test_start_active_record test_strategy
      new_state = {}

      table_name = active_record_table
      if PseudoCleaner::Configuration.db_connection(:active_record).connection.columns(table_name).find { |column| column.name == "id" }
        new_state[:max_id] = PseudoCleaner::Configuration.db_connection(:active_record).connection.
            execute("SELECT MAX(`id`) FROM `#{table_name}`").first[0] || 0

        if @options[:output_diagnostics]
          if @report_table
            @report_table.write_stats("max(id)", new_state[:max_id])
          else
            PseudoCleaner::Logger.write("    max(id) = #{new_state[:max_id]}")
          end
        end
      end

      [:created, :updated].each do |date_name|
        [:at, :on].each do |verb_name|
          date_column_name = "#{date_name}_#{verb_name}"

          if PseudoCleaner::Configuration.db_connection(:active_record).connection.
              columns(table_name).find { |column| column.name == date_column_name }
            new_state[date_name] = {
                column_name: date_column_name,
                value:       PseudoCleaner::Configuration.db_connection(:active_record).connection.
                    execute("SELECT MAX(`#{date_column_name}`) FROM `#{table_name}`").first[0] ||
                                 Time.now - 1.second
            }
            if @options[:output_diagnostics]
              if @report_table
                @report_table.write("max(#{new_state[date_name][:column_name]})", new_state[date_name][:value])
              else
                PseudoCleaner::Logger.write("    max(#{new_state[date_name][:column_name]}) = #{new_state[date_name][:value]}")
              end
            end

            break
          end
        end
      end

      new_state[:blank] = new_state.blank?
      new_state[:count] = PseudoCleaner::Configuration.db_connection(:active_record).connection.
          execute("SELECT COUNT(*) FROM `#{table_name}`").first[0]

      @@initial_states[@table] = @@initial_states[@table].merge new_state
    end

    def test_start_sequel_model test_strategy
      new_state    = {}
      access_table = sequel_model_table

      if access_table.columns.include?(:id)
        new_state[:max_id] = access_table.unfiltered.max(:id) || 0
        if @options[:output_diagnostics]
          if @report_table
            @report_table.write_stats("max(id)", new_state[:max_id])
          else
            PseudoCleaner::Logger.write("    max(id) = #{new_state[:max_id]}")
          end
        end
      end

      [:created, :updated].each do |date_name|
        [:at, :on].each do |verb_name|
          date_column_name = "#{date_name}_#{verb_name}".to_sym

          if access_table.columns.include?(date_column_name)
            new_state[date_name] = {
                column_name: date_column_name,
                value:       access_table.unfiltered.max(date_column_name) || Time.now - 1.second
            }
            if @options[:output_diagnostics]
              if @report_table
                @report_table.write_stats("max(#{new_state[date_name][:column_name]})", new_state[date_name][:value])
              else
                PseudoCleaner::Logger.write("    max(#{new_state[date_name][:column_name]}) = #{new_state[date_name][:value]}")
              end
            end

            break
          end
        end
      end

      new_state[:blank] = new_state.blank?
      new_state[:count] = access_table.unfiltered.count

      @@initial_states[@table] = @@initial_states[@table].merge new_state
    end

    def test_end test_strategy
      initial_state = @@initial_states[@table]

      within_report_block(initial_state[:table_name], @options[:output_diagnostics]) do
        reset_table test_strategy, false
      end
    end

    def suite_end test_strategy
      initial_state = @@initial_states[@table]

      within_report_block(initial_state[:table_name], @options[:output_diagnostics]) do
        reset_table test_strategy, true
      end
    end

    def reset_table test_strategy, require_output
      initial_state = @@initial_states[@table]

      if @test_strategy != test_strategy && !PseudoCleaner::Configuration.current_instance.single_cleaner_set
        if @options[:output_diagnostics]
          PseudoCleaner::MasterCleaner.report_error

          if @report_table
            @report_table.write_stats("WARNING", "*** The ending strategy for \"#{initial_state[:table_name]}\" changed! ***")
          else
            PseudoCleaner::Logger.write("  *** The ending strategy for \"#{initial_state[:table_name]}\" changed! ***".red.on_light_white)
          end
        end
      end

      if test_strategy == :pseudo_delete || PseudoCleaner::Configuration.current_instance.post_transaction_analysis
        # we should check the relationships for any records which still refer to
        # a now deleted record.  (i.e. if we updated a record to refer to a record)
        # we deleted...
        #
        # Which is why this is not a common or particularly good solution.
        #
        # I'm using it because it is faster than reseeding each test...
        # And, I can be responsible for worrying about referential integrity in the test
        # if I want to...
        pre_string = "  Resetting table \"#{initial_state[:table_name]}\" for #{test_strategy}..."
        pre_string = "Tests ended without cleaning up properly!!!\n" + pre_string if require_output
        pre_string = pre_string.red.on_light_white if require_output

        require_output ||= @options[:output_diagnostics]

        if initial_state[:table_is_active_record]
          test_end_active_record test_strategy, pre_string, require_output
        end

        if initial_state[:table_is_sequel_model]
          test_end_sequel_model test_strategy, pre_string, require_output
        end
      end
    end

    def test_end_active_record test_strategy, pre_string, require_output
      initial_state = @@initial_states[@table]
      cleaned_table = false

      table_name = active_record_table
      if initial_state[:max_id]
        the_max = initial_state[:max_id] || 0

        PseudoCleaner::Configuration.db_connection(:active_record).connection.
            execute("DELETE FROM `#{table_name}` WHERE id > #{the_max}")
        num_deleted = PseudoCleaner::Configuration.db_connection(:active_record).connection.raw_connection.affected_rows

        if num_deleted > 0
          cleaned_table = true

          pre_string = output_delete_record(test_strategy,
                                            "    Deleted #{num_deleted} records by ID.",
                                            "Deleted",
                                            "#{num_deleted} records by ID",
                                            pre_string,
                                            require_output)
        end
      end

      if initial_state[:created]
        PseudoCleaner::Configuration.db_connection(:active_record).connection.
            execute("DELETE FROM `#{table_name}` WHERE #{initial_state[:created][:column_name]} > '#{initial_state[:created][:value]}'")
        num_deleted = PseudoCleaner::Configuration.db_connection(:active_record).connection.raw_connection.affected_rows

        if num_deleted > 0
          cleaned_table = true

          pre_string = output_delete_record(test_strategy,
                                            "    Deleted #{num_deleted} records by #{initial_state[:created][:column_name]}.",
                                            "Deleted",
                                            "#{num_deleted} records by #{initial_state[:created][:column_name]}",
                                            pre_string,
                                            require_output)
        end
      end

      if initial_state[:updated]
        dirty_count = PseudoCleaner::Configuration.db_connection(:active_record).connection.
            execute("SELECT COUNT(*) FROM `#{table_name}` WHERE #{initial_state[:updated][:column_name]} > '#{initial_state[:updated][:value]}'").first[0]

        if require_output && dirty_count > 0
          # cleaned_table = true

          initial_state[:updated][:value] = PseudoCleaner::Configuration.db_connection(:active_record).connection.
              execute("SELECT MAX(#{initial_state[:updated][:column_name]}) FROM `#{table_name}`").first[0]

          pre_string = output_delete_record(test_strategy,
                                            "    *** There are #{dirty_count} records which have been updated and may be dirty remaining after cleaning \"#{initial_state[:table_name]}\"... ***".red.on_light_white,
                                            "WARNING",
                                            "*** There are #{dirty_count} records which have been updated and may be dirty remaining after cleaning \"#{initial_state[:table_name]}\"... ***",
                                            pre_string,
                                            require_output)
        end
      end

      final_count = PseudoCleaner::Configuration.db_connection(:active_record).connection.
          execute("SELECT COUNT(*) FROM `#{table_name}`").first[0]
      if initial_state[:count] == 0
        if initial_state[:blank]
          cleaned_table = true

          DatabaseCleaner[:active_record, connection: PseudoCleaner::Configuration.db_connection(:active_record)].
              clean_with(:truncation, only: [initial_state[:table_name]])
          if final_count > 0
            pre_string = output_delete_record(test_strategy,
                                              "    Deleted #{final_count} records by cleaning the table.",
                                              "Deleted",
                                              "#{final_count} records by cleaning the table",
                                              pre_string,
                                              require_output)
          end

          final_count = PseudoCleaner::Configuration.db_connection(:active_record).connection.
              execute("SELECT COUNT(*) FROM `#{table_name}`").first[0]
        end
      end

      if initial_state[:count] != final_count
        pre_string = output_delete_record(test_strategy,
                                          "    *** There are #{final_count - initial_state[:count]} dirty records remaining after cleaning \"#{initial_state[:table_name]}\"... ***".red.on_light_white,
                                          "WARNING",
                                          "*** There are #{final_count - initial_state[:count]} dirty records remaining after cleaning \"#{initial_state[:table_name]}\"... ***",
                                          pre_string,
                                          true)

        initial_state[:count] = final_count
        cleaned_table         = true
      end

      if cleaned_table
        reset_auto_increment true
      end
    end

    def test_end_sequel_model test_strategy, pre_string, require_output
      initial_state = @@initial_states[@table]
      access_table  = sequel_model_table
      cleaned_table = false

      if access_table
        if initial_state[:max_id]
          the_max     = initial_state[:max_id] || 0
          num_deleted = access_table.unfiltered.where { id > the_max }.delete
          if num_deleted > 0
            cleaned_table = true

            pre_string = output_delete_record(test_strategy,
                                              "    Deleted #{num_deleted} records by ID.",
                                              "Deleted",
                                              "#{num_deleted} records by ID",
                                              pre_string,
                                              require_output)
          end
        end

        if initial_state[:created]
          num_deleted = access_table.
              unfiltered.
              where("`#{initial_state[:created][:column_name]}` > ?", initial_state[:created][:value]).
              delete
          if num_deleted > 0
            cleaned_table = true

            pre_string = output_delete_record(test_strategy,
                                              "    Deleted #{num_deleted} records by #{initial_state[:created][:column_name]}.",
                                              "Deleted",
                                              "#{num_deleted} records by #{initial_state[:created][:column_name]}",
                                              pre_string,
                                              require_output)
          end
        end

        if initial_state[:updated]
          dirty_count = access_table.
              unfiltered.
              where("`#{initial_state[:updated][:column_name]}` > ?", initial_state[:updated][:value]).
              count

          if require_output && dirty_count > 0
            # cleaned_table = true

            initial_state[:updated][:value] = access_table.unfiltered.max(initial_state[:updated][:column_name])

            pre_string = output_delete_record(test_strategy,
                                              "    *** There are #{dirty_count} records which have been updated and may be dirty remaining after cleaning \"#{initial_state[:table_name]}\"... ***".red.on_light_white,
                                              "WARNING",
                                              "*** There are #{dirty_count} records which have been updated and may be dirty remaining after cleaning \"#{initial_state[:table_name]}\"... ***",
                                              pre_string,
                                              require_output)
          end
        end

        final_count = access_table.unfiltered.count
        if initial_state[:count] == 0
          if initial_state[:blank]
            cleaned_table = true

            DatabaseCleaner[:sequel, connection: PseudoCleaner::Configuration.db_connection(:sequel)].
                clean_with(:truncation, only: [initial_state[:table_name]])
            if final_count > 0
              pre_string = output_delete_record(test_strategy,
                                                "    Deleted #{final_count} records by cleaning the table.",
                                                "Deleted",
                                                "#{final_count} records by cleaning the table",
                                                pre_string,
                                                require_output)
            end

            final_count = access_table.unfiltered.count
          end
        end

        if initial_state[:count] != final_count
          pre_string = output_delete_record(test_strategy,
                                            "    *** There are #{final_count - initial_state[:count]} dirty records remaining after cleaning \"#{initial_state[:table_name]}\"... ***".red.on_light_white,
                                            "WARNING",
                                            "*** There are #{final_count - initial_state[:count]} dirty records remaining after cleaning \"#{initial_state[:table_name]}\"... ***",
                                            pre_string,
                                            true)

          initial_state[:count] = final_count
          cleaned_table         = true
        end

        if cleaned_table
          reset_auto_increment true
        end
      end
    end

    def output_delete_record(test_strategy,
                             stats_string,
                             table_label,
                             table_value,
                             pre_string,
                             require_output = false)
      if pre_string && !@report_table && (@options[:output_diagnostics] || require_output)
        PseudoCleaner::Logger.write(pre_string)
      end

      if test_strategy == :transaction
        PseudoCleaner::Logger.write("    ***** TRANSACTION FAILED!!! *****".red.on_light_white)
      end

      if @options[:output_diagnostics] || require_output
        PseudoCleaner::MasterCleaner.report_error

        if @report_table
          @report_table.write_stats(table_label, table_value)
        else
          PseudoCleaner::Logger.write(stats_string)
        end
      end

      nil
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
      initial_state = @@initial_states[@table]

      if initial_state[:max_id]
        table_name = active_record_table

        unless table_name.blank?
          if @options[:output_diagnostics]
            if @report_table
              @report_table.write_stats("AUTO_INCREMENT", initial_state[:max_id] + 1)
            else
              PseudoCleaner::Logger.write("    ALTER TABLE #{table_name} AUTO_INCREMENT = #{initial_state[:max_id] + 1}")
            end
          end

          PseudoCleaner::Configuration.db_connection(:active_record).connection.
              execute("ALTER TABLE #{table_name} AUTO_INCREMENT = #{initial_state[:max_id] + 1}")
        end
      end
    end

    def reset_auto_increment_sequel_model
      initial_state = @@initial_states[@table]

      if initial_state[:max_id]
        table_name = sequel_model_table_name

        unless table_name.blank?
          if @options[:output_diagnostics]
            if @report_table
              @report_table.write_stats("AUTO_INCREMENT", initial_state[:max_id] + 1)
            else
              PseudoCleaner::Logger.write("    ALTER TABLE #{table_name} AUTO_INCREMENT = #{initial_state[:max_id] + 1}")
            end
          end

          PseudoCleaner::Configuration.db_connection(:sequel)["ALTER TABLE #{table_name} AUTO_INCREMENT = #{initial_state[:max_id] + 1}"].first
        end
      end
    end

    def <=>(other_object)
      if (other_object.is_a?(PseudoCleaner::TableCleaner))
        return 0 if other_object.table == self.table

        SortedSeeder::Seeder.create_order.each do |create_table|
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
      table_dataset = nil

      if symbol_table?
        table_dataset = PseudoCleaner::Configuration.db_connection(:sequel)[table]
      else
        if sequel_model_table_name
          table_dataset = PseudoCleaner::Configuration.db_connection(:sequel)[sequel_model_table_name.gsub(/`([^`]+)`/, "\\1").to_sym]
        end
        unless table_dataset && table_dataset.is_a?(Sequel::Mysql2::Dataset)
          table_dataset = table.dataset
        end
      end
      unless table_dataset && table_dataset.is_a?(Sequel::Mysql2::Dataset)
        table_dataset = nil
      end

      table_dataset
    end

    def sequel_model_table_name
      if symbol_table?
        "`#{table}`"
      elsif table.simple_table
        table.simple_table
      elsif table.table_name
        "`#{table.table_name}`"
      else
        nil
      end
    end

    def review_rows(&block)
      initial_state = @@initial_states[@table]

      if initial_state
        if initial_state[:table_is_active_record]
          review_rows_active_record &block
        end

        if initial_state[:table_is_sequel_model]
          review_rows_sequel_model &block
        end
      end
    end

    def review_rows_active_record(&block)
      initial_state  = @@initial_states[@table]
      table_name     = active_record_table
      dataset_sequel = nil

      if initial_state[:max_id]
        the_max = initial_state[:max_id] || 0

        dataset_sequel = "SELECT * FROM `#{table_name}` WHERE id > #{the_max}"
      elsif initial_state[:created]
        dataset_sequel = "SELECT * FROM `#{table_name}` WHERE #{initial_state[:created][:column_name]} > '#{initial_state[:created][:value]}'"
      elsif initial_state[:updated]
        dataset_sequel = "SELECT * FROM `#{table_name}` WHERE #{initial_state[:updated][:column_name]} > '#{initial_state[:updated][:value]}'"
      elsif initial_state[:count]
        dataset_sequel = "SELECT * FROM `#{table_name}` LIMIT 99 OFFSET #{initial_state[:count]}"
      end

      columns = PseudoCleaner::Configuration.db_connection(:active_record).connection.columns(table_name)
      PseudoCleaner::Configuration.db_connection(:active_record).connection.execute(dataset_sequel).each do |row|
        col_index = 0
        data_hash = columns.reduce({}) do |hash, column_name|
          hash[column_name.name] = row[col_index]
          col_index              += 1

          hash
        end

        block.yield table_name, data_hash
      end
    end

    def review_rows_sequel_model(&block)
      initial_state = @@initial_states[@table]
      dataset       = nil

      if initial_state[:max_id]
        dataset = sequel_model_table.unfiltered.where { id > initial_state[:max_id] || 0 }
      elsif initial_state[:created]
        dataset = sequel_model_table.
            unfiltered.
            where("`#{initial_state[:created][:column_name]}` > ?", initial_state[:created][:value])
      elsif initial_state[:updated]
        dataset = sequel_model_table.
            unfiltered.
            where("`#{initial_state[:updated][:column_name]}` > ?", initial_state[:created][:value])
      elsif initial_state[:count]
        dataset = sequel_model_table.unfiltered.limit(99, initial_state[:count])
      end

      if dataset
        dataset.each do |row|
          block.yield sequel_model_table_name.gsub(/`([^`]+)`/, "\\1"), row
        end
      end
    end
  end
end