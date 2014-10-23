module PseudoCleaner
  class MasterCleaner
    @@suite_cleaner = nil

    CLEANING_STRATEGIES            = [:transaction, :truncation, :deletion, :pseudo_delete, :none]
    DB_CLEANER_CLEANING_STRATEGIES =
        {
            transaction:   :transaction,
            truncation:    :truncation,
            deletion:      :deletion,
            pseudo_delete: :transaction
        }
    VALID_TEST_TYPES               = [:suite, :test]

    class << self
      def start_suite
        @@suite_cleaner = PseudoCleaner::MasterCleaner.new(:suite)
        @@suite_cleaner.start :pseudo_delete
        @@suite_cleaner
      end

      def start_example(example_class, strategy)
        pseudo_cleaner_data = {}
        pseudo_cleaner_data[:test_strategy] = strategy

        unless strategy == :none
          DatabaseCleaner.strategy = PseudoCleaner::MasterCleaner::DB_CLEANER_CLEANING_STRATEGIES[strategy]
          unless strategy == :pseudo_delete
            DatabaseCleaner.start
          end

          pseudo_cleaner_data[:pseudo_state] = PseudoCleaner::MasterCleaner.start_test strategy
        end

        example_class.instance_variable_set(:@pseudo_cleaner_data, pseudo_cleaner_data)
      end

      def end_example(example_class)
        pseudo_cleaner_data = example_class.instance_variable_get(:@pseudo_cleaner_data)

        unless pseudo_cleaner_data[:test_strategy] == :none
          unless pseudo_cleaner_data[:test_strategy] == :pseudo_delete
            DatabaseCleaner.clean
          end

          case pseudo_cleaner_data[:test_strategy]
            when :deletion, :truncation
              PseudoCleaner::MasterCleaner.database_reset
          end

          pseudo_cleaner_data[:pseudo_state].end
        end
      end

      def end_suite
        @@suite_cleaner.end :pseudo_delete if @@suite_cleaner
      end

      def start_test test_strategy
        cleaner = PseudoCleaner::MasterCleaner.new(:test)
        cleaner.start test_strategy

        cleaner
      end

      def clean(test_type, test_strategy, &block)
        master_cleaner = PseudoCleaner::MasterCleaner.send "start_#{test_type}", test_strategy

        body_error = nil
        begin
          block.yield master_cleaner
        rescue => error
          body_error = error
        end

        master_cleaner.end

        raise body_error if body_error
      end

      def reset_database
        DatabaseCleaner.clean_with(:truncation)

        PseudoCleaner::MasterCleaner.database_reset
      end

      def database_reset
        PseudoCleaner::MasterCleaner.seed_data
        PseudoCleaner::MasterCleaner.start_suite
      end

      def seed_data
        PseudoCleaner::Logger.write("Re-seeding database".red.on_light_white)
        Seedling::Seeder.seed_all
      end

      def process_exception(error)
        PseudoCleaner::Logger.write("    An exception has occurred:".red.on_light_white)
        PseudoCleaner::Logger.write("")
        PseudoCleaner::Logger.write(error.to_s)
        PseudoCleaner::Logger.write(error.backtrace.join("\n")) if error.backtrace
      end
    end

    def initialize(test_type)
      raise "Invalid test type.  Must be one of: #{VALID_TEST_TYPES}" unless VALID_TEST_TYPES.include?(test_type)

      @test_type = test_type
    end

    def start(test_strategy, options = {})
      @cleaners      = []
      @test_strategy = test_strategy

      create_table_cleaners options
      create_custom_cleaners options

      seed_sorts = @cleaners.map { |cleaner| Seedling::Seeder::SeederSorter.new(cleaner) }
      seed_sorts.sort!

      @cleaners = seed_sorts.map(&:seed_base_object)

      start_all_cleaners options
    end

    def end(options = {})
      if PseudoCleaner::Configuration.current_instance.output_diagnostics
        PseudoCleaner::Logger.write("Cleaning #{@test_type}")
      end
      end_all_cleaners options
    end

    def create_table_cleaners(options = {})
      Seedling::Seeder.create_order.each do |table|
        cleaner_class = PseudoCleaner::TableCleaner.cleaner_class(table)
        if cleaner_class
          @cleaners << cleaner_class.new("#{@test_type}_start".to_sym, "#{@test_type}_end".to_sym, table, options)
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
              PseudoCleaner::TableCleaner::VALID_TEST_METHODS.any? { |test_method| check_class.instance_methods.include?(test_method) }
            unless @cleaners.any? { |cleaner| check_class.name == cleaner.class.name }
              @cleaners << check_class.new("#{@test_type}_start".to_sym, "#{@test_type}_end".to_sym, nil, options)
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

    def start_all_cleaners(options)
      run_all_cleaners("#{@test_type}_start".to_sym, @cleaners, options)
    end

    def end_all_cleaners(options)
      run_all_cleaners("#{@test_type}_end".to_sym, @cleaners.reverse, options)
    end

    def run_all_cleaners(cleaner_function, cleaners, options)
      last_error = nil

      cleaners.each do |cleaner|
        begin
          if cleaner.respond_to?(cleaner_function)
            cleaner.send(cleaner_function, @test_strategy)
          end
        rescue => error
          PseudoCleaner::MasterCleaner.process_exception(last_error) if last_error

          last_error = error
        end
      end

      raise last_error if last_error
    end
  end
end