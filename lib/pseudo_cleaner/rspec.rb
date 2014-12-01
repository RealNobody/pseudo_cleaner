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

  config.before(:each) do |example|
    new_strategy = nil

    clean_example = example
    clean_example = example.example if example.respond_to?(:example)

    new_strategy = clean_example.metadata[:strategy]

    if new_strategy && !PseudoCleaner::MasterCleaner::CLEANING_STRATEGIES.include?(new_strategy)
      PseudoCleaner::Logger.write "*** Unknown/invalid cleaning strategy #{clean_example.metadata[:strategy]}.  Using default: :transaction ***".red.on_light_white
      new_strategy = :transaction
    end
    if clean_example.metadata[:js]
      new_strategy ||= :pseudo_delete
      new_strategy = :pseudo_delete if new_strategy == :transaction
    end
    new_strategy ||= :transaction

    PseudoCleaner::MasterCleaner.start_example(clean_example, new_strategy)
  end

  config.after(:each) do |example|
    clean_example = example
    clean_example = example.example if example.respond_to?(:example)

    PseudoCleaner::MasterCleaner.end_example(clean_example)
  end
end