RSpec.configure do |config|
  config.before(:suite) do
    PseudoCleaner::MasterCleaner.reset_database

    # We start suite in case a custom cleaner wants/needs to.
    DatabaseCleaner.strategy = :transaction
  end

  config.after(:suite) do
    # We end suite in case a custom cleaner wants/needs to.
    PseudoCleaner::MasterCleaner.end_suite
  end

  config.before(:each) do |example|
    example = examle.example if example.respond_to?(:example)

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

    PseudoCleaner::MasterCleaner.start_example(example, new_strategy)
  end

  config.after(:each) do |example|
    PseudoCleaner::MasterCleaner.end_example(example)
  end
end