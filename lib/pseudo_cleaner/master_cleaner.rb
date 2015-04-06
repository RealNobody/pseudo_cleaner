require "sorted_seeder"

module PseudoCleaner
  class MasterCleaner
    @@suite_cleaner          = nil
    @@cleaner_classes        = nil
    @@cleaner_classes_sorted = false

    CLEANING_STRATEGIES            = [:transaction, :truncation, :deletion, :pseudo_delete, :none]
    DB_CLEANER_CLEANING_STRATEGIES =
        {
            transaction:   :transaction,
            truncation:    :truncation,
            deletion:      :deletion,
            pseudo_delete: :transaction
        }
    VALID_TEST_TYPES               = [:suite, :test]

    VALID_START_METHODS = [:test_start, :suite_start]
    VALID_END_METHODS   = [:test_end, :suite_end]
    VALID_TEST_METHODS  = VALID_START_METHODS + VALID_END_METHODS

    class << self
      def start_suite
        if @@suite_cleaner
          @@suite_cleaner.reset_suite
        end
        @@suite_cleaner = PseudoCleaner::MasterCleaner.new(:suite)
        @@suite_cleaner.start :pseudo_delete
        @@suite_cleaner
      end

      def database_cleaner
        if Object.const_defined?("ActiveRecord", false) && ActiveRecord.const_defined?("Base", false)
          DatabaseCleaner[:active_record, connection: PseudoCleaner::Configuration.db_connection(:active_record)]
        elsif Object.const_defined?("Sequel", false) && Sequel.const_defined?("Model", false)
          DatabaseCleaner[:sequel, connection: PseudoCleaner::Configuration.db_connection(:sequel)]
        end
      end

      def start_example(example_class, strategy)
        pseudo_cleaner_data                 = {}
        pseudo_cleaner_data[:test_strategy] = strategy

        unless strategy == :none
          raise "invalid strategy" unless PseudoCleaner::MasterCleaner::DB_CLEANER_CLEANING_STRATEGIES.has_key? strategy

          DatabaseCleaner.strategy = PseudoCleaner::MasterCleaner::DB_CLEANER_CLEANING_STRATEGIES[strategy]
          unless [:pseudo_delete].include? strategy
            PseudoCleaner::MasterCleaner.database_cleaner.start
          end

          pseudo_cleaner_data[:pseudo_state] = PseudoCleaner::MasterCleaner.start_test strategy
        end

        example_class.instance_variable_set(:@pseudo_cleaner_data, pseudo_cleaner_data)
      end

      def end_example(example_class)
        pseudo_cleaner_data = example_class.instance_variable_get(:@pseudo_cleaner_data)

        unless pseudo_cleaner_data[:test_strategy] == :none
          unless [:pseudo_delete].include? pseudo_cleaner_data[:test_strategy]
            PseudoCleaner::MasterCleaner.database_cleaner.clean
          end

          case pseudo_cleaner_data[:test_strategy]
            when :deletion, :truncation
              PseudoCleaner::MasterCleaner.database_reset
          end

          pseudo_cleaner_data[:pseudo_state].end test_type: :test, test_strategy: pseudo_cleaner_data[:test_strategy]
        end
      end

      def end_suite
        @@suite_cleaner.end test_strategy: :pseudo_delete if @@suite_cleaner
      end

      def start_test test_strategy
        raise "Invalid test_strategy \"#{test_strategy}\"" unless CLEANING_STRATEGIES.include? test_strategy

        cleaner = if PseudoCleaner::Configuration.current_instance.single_cleaner_set
                    @@suite_cleaner
                  else
                    PseudoCleaner::MasterCleaner.new(:test)
                  end

        cleaner.start test_strategy, test_type: :test, test_strategy: test_strategy

        cleaner
      end

      def clean(test_type, test_strategy, &block)
        raise "Invalid test_type \"#{test_type}\"" unless [:suite, :test].include? test_type
        raise "Invalid test_strategy \"#{test_strategy}\"" unless CLEANING_STRATEGIES.include? test_strategy

        master_cleaner = PseudoCleaner::MasterCleaner.send "start_#{test_type}", test_strategy

        body_error = nil
        begin
          block.yield master_cleaner
        rescue => error
          body_error = error
        end

        master_cleaner.end test_type: test_type, test_strategy: test_strategy

        raise body_error if body_error
      end

      def reset_database
        PseudoCleaner::MasterCleaner.database_cleaner.clean_with(:truncation)

        PseudoCleaner::MasterCleaner.database_reset
      end

      def database_reset
        PseudoCleaner::MasterCleaner.seed_data
        PseudoCleaner::MasterCleaner.start_suite
      end

      def seed_data
        PseudoCleaner::Logger.write("Re-seeding database".red.on_light_white)
        SortedSeeder::Seeder.seed_all(PseudoCleaner::Configuration.db_connection(nil))
      end

      def process_exception(error)
        PseudoCleaner::Logger.write("    An exception has occurred:".red.on_light_white)
        PseudoCleaner::Logger.write("")
        PseudoCleaner::Logger.write(error.to_s)
        PseudoCleaner::Logger.write(error.backtrace.join("\n")) if error.backtrace
      end

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

      def cleaner_classes
        unless @@cleaner_classes
          @@cleaner_classes = []

          PseudoCleaner::MasterCleaner.create_table_cleaners
          PseudoCleaner::MasterCleaner.create_custom_cleaners
        end

        @@cleaner_classes
      end

      def create_table_cleaners(options = {})
        SortedSeeder::Seeder.create_order(PseudoCleaner::Configuration.db_connection(nil)).each do |table|
          cleaner_class = PseudoCleaner::MasterCleaner.cleaner_class(table.name)
          if cleaner_class
            PseudoCleaner::MasterCleaner.cleaner_classes << [table, nil, cleaner_class]
          end
        end
        if SortedSeeder::Seeder.respond_to?(:unclassed_tables)
          SortedSeeder::Seeder.unclassed_tables(PseudoCleaner::Configuration.db_connection(nil)).each do |table_name|
            cleaner_class = PseudoCleaner::MasterCleaner.cleaner_class(table_name)
            if cleaner_class
              PseudoCleaner::MasterCleaner.cleaner_classes << [nil, table_name, cleaner_class]
            end
          end
        end
      end

      def create_custom_cleaners(options = {})
        if Object.const_defined?("Rails", false)
          cleaner_root  = Rails.root.join("db/cleaners/").to_s
          cleaner_files = Dir[Rails.root.join("db/cleaners/**/*.rb")]

          cleaner_files.each do |cleaner_file|
            class_name = File.basename(cleaner_file, ".rb").classify

            check_class, full_module_name = find_file_class(cleaner_file, cleaner_root)
            unless check_class && check_class.const_defined?(class_name, false)
              require cleaner_file
              check_class, full_module_name = find_file_class(cleaner_file, cleaner_root)
            end

            if check_class
              full_module_name << class_name
              if check_class.const_defined?(class_name, false)
                check_class = full_module_name.join("::").constantize
              else
                check_class = nil
              end
            end

            if check_class &&
                PseudoCleaner::MasterCleaner::VALID_TEST_METHODS.
                    any? { |test_method| check_class.instance_methods.include?(test_method) }
              unless PseudoCleaner::MasterCleaner.cleaner_classes.any? { |cleaner| check_class == cleaner[2] }
                PseudoCleaner::MasterCleaner.cleaner_classes << [nil, nil, check_class]
              end
            end
          end
        end
      end

      def find_file_class(seeder_file, seeder_root)
        check_class      = Object
        full_module_name = []

        File.dirname(seeder_file.to_s[seeder_root.length..-1]).split("/").map do |module_element|
          if (module_element != ".")
            full_module_name << module_element.classify
            if check_class.const_defined?(full_module_name[-1], false)
              check_class = full_module_name.join("::").constantize
            else
              check_class = nil
              break
            end
          end
        end

        return check_class, full_module_name
      end

      def review_rows(&block)
        @@suite_cleaner.review_rows &block
      end
    end

    def initialize(test_type)
      raise "Invalid test type.  Must be one of: #{VALID_TEST_TYPES}" unless VALID_TEST_TYPES.include?(test_type)

      @test_type = test_type
    end

    def start(test_strategy, options = {})
      test_type = options[:test_type] || @test_type

      unless @cleaners
        @cleaners      = []
        @test_strategy = test_strategy

        start_method = "#{test_type}_start".to_sym
        end_method   = "#{test_type}_end".to_sym

        PseudoCleaner::MasterCleaner.cleaner_classes.each do |clean_class|
          table = clean_class[0]
          table ||= clean_class[1]

          begin
            @cleaners << clean_class[2].new(start_method, end_method, table, options)
          rescue Exception => error
            puts error.to_s
            raise error
          end
        end

        unless @@cleaner_classes_sorted
          seed_sorts = @cleaners.map { |cleaner| SortedSeeder::Seeder::SeederSorter.new(cleaner) }
          seed_sorts.sort!

          @cleaners = seed_sorts.map(&:seed_base_object)

          sorted_classes = []
          @cleaners.each do |cleaner|
            cleaner_class = PseudoCleaner::MasterCleaner.cleaner_classes.detect do |unsorted_cleaner|
              if cleaner.class == unsorted_cleaner[2]
                if unsorted_cleaner[2] == PseudoCleaner::TableCleaner
                  cleaner.table == unsorted_cleaner[0] || cleaner.table == unsorted_cleaner[1]
                else
                  true
                end
              end
            end

            sorted_classes << cleaner_class
          end

          @@cleaner_classes        = sorted_classes
          @@cleaner_classes_sorted = true
        end
      end

      start_all_cleaners options
    end

    def end(options = {})
      test_type = options[:test_type] || @test_type
      if PseudoCleaner::Configuration.current_instance.output_diagnostics ||
          PseudoCleaner::Configuration.current_instance.post_transaction_analysis
        PseudoCleaner::Logger.write("Cleaning #{test_type}")
      end
      end_all_cleaners options
    end

    def start_all_cleaners(options)
      test_type     = options[:test_type] || @test_type
      test_strategy = options[:test_strategy] || @test_strategy
      run_all_cleaners("#{test_type}_start".to_sym, @cleaners, test_strategy)
    end

    def end_all_cleaners(options)
      test_type     = options[:test_type] || @test_type
      test_strategy = options[:test_strategy] || @test_strategy
      run_all_cleaners("#{test_type}_end".to_sym, @cleaners.reverse, test_strategy)
    end

    def reset_suite
      run_all_cleaners(:reset_suite, @cleaners.reverse)
    end

    def run_all_cleaners(cleaner_function, cleaners, *args, &block)
      last_error = nil

      if cleaners
        cleaners.each do |cleaner|
          begin
            if cleaner.respond_to?(cleaner_function)
              cleaner.send(cleaner_function, *args, &block)
            end
          rescue => error
            PseudoCleaner::MasterCleaner.process_exception(last_error) if last_error

            last_error = error
          end
        end
      end

      raise last_error if last_error
    end

    def review_rows(&block)
      run_all_cleaners(:review_rows, @cleaners, &block)
    end
  end
end