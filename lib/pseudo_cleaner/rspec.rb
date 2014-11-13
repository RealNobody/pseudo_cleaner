RSpec.configure do |config|
  config.before(:suite) do
    if PseudoCleaner::Configuration.current_instance.clean_database_before_tests
      PseudoCleaner::MasterCleaner.reset_database
    else
      PseudoCleaner::MasterCleaner.start_suite
    end

    # We start suite in case a custom cleaner wants/needs to.
    DatabaseCleaner.strategy = :transaction
  end

  config.after(:suite) do
    # We end suite in case a custom cleaner wants/needs to.
    PseudoCleaner::MasterCleaner.end_suite
  end

  config.around(:each) do |run_example|
    example = run_example.example if run_example.respond_to?(:example)

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

    if new_strategy != :transaction
      PseudoCleaner::MasterCleaner.start_example(example, new_strategy)
      run_example.run
      PseudoCleaner::MasterCleaner.end_example(example)
    else
      PseudoCleaner::MasterCleaner.start_example(example, new_strategy)
      DatabaseCleaner.cleaning do
        run_example.run
      end
      PseudoCleaner::MasterCleaner.end_example(example)
    end
  end
end