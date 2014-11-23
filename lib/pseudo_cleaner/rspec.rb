RSpec.configure do |config|
  config.before(:suite) do
    timing = Benchmark.measure do
      if PseudoCleaner::Configuration.current_instance.clean_database_before_tests
        PseudoCleaner::MasterCleaner.reset_database
      else
        PseudoCleaner::MasterCleaner.start_suite
      end

      # We start suite in case a custom cleaner wants/needs to.
      DatabaseCleaner.strategy = :transaction
    end
    PseudoCleaner::MasterCleaner.add_timing(:suite, timing)
    PseudoCleaner::MasterCleaner.add_timing(:total, timing)
  end

  config.after(:suite) do
    timing = Benchmark.measure do
      # We end suite in case a custom cleaner wants/needs to.
      PseudoCleaner::MasterCleaner.end_suite
    end
    PseudoCleaner::MasterCleaner.add_timing(:suite, timing)
    PseudoCleaner::MasterCleaner.add_timing(:total, timing)

    PseudoCleaner::MasterCleaner.print_timings
  end

  config.before(:each) do |example|
    new_strategy = nil

    timing = Benchmark.measure do
      clean_example = example
      clean_example = example.example if example.respond_to?(:example)

      new_strategy = example.metadata[:strategy]

      if new_strategy && !PseudoCleaner::MasterCleaner::CLEANING_STRATEGIES.include?(new_strategy)
        PseudoCleaner::Logger.write "*** Unknown/invalid cleaning strategy #{example.metadata[:strategy]}.  Using default: :transaction ***".red.on_light_white
        new_strategy = :transaction
      end
      if example.metadata[:js]
        new_strategy ||= :pseudo_delete
        new_strategy = :pseudo_delete if new_strategy == :transaction
      end
      new_strategy ||= :transaction

      PseudoCleaner::MasterCleaner.start_example(clean_example, new_strategy)
    end

    PseudoCleaner::MasterCleaner.add_timing(new_strategy, timing)
    PseudoCleaner::MasterCleaner.add_timing(:rspec_each, timing)
    PseudoCleaner::MasterCleaner.add_timing(:total, timing)
  end

  config.after(:each) do |example|
    timing = Benchmark.measure do
      clean_example = example
      clean_example = example.example if example.respond_to?(:example)

      PseudoCleaner::MasterCleaner.end_example(clean_example)
    end

    pseudo_cleaner_data = clean_example.instance_variable_get(:@pseudo_cleaner_data)
    PseudoCleaner::MasterCleaner.add_timing(pseudo_cleaner_data[:test_strategy], timing)
    PseudoCleaner::MasterCleaner.add_timing(:rspec_each, timing)
    PseudoCleaner::MasterCleaner.add_timing(:total, timing)
  end
end
