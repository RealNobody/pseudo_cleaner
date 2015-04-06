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

  # I tried making this a config.around(:each).
  # You can't do that.  It turns out that RSpec injects a virtual around(:each) that
  # calls after_teardown which calls ActiveRecord::Base.clear_active_connections!
  #
  # This resets the active connection.
  #
  # If (for whatever reason) there are multiple connections in the connection pool this
  # means that when you go to clean, the connection has been released, and when
  # DatabaseCleaner tries to get a new connection, it may not get the same one it had
  # when start was called.
  #
  # By using before and after, we avoid this problem by being inside the around block.
  # The compromize is that the user will be more load dependent to get the hooks
  # in the right order (potentially).
  config.before(:each) do |example|
    test_example = example
    test_example = example.example if example.respond_to?(:example)

    new_strategy = nil

    new_strategy = test_example.metadata[:strategy]

    if new_strategy && !PseudoCleaner::MasterCleaner::CLEANING_STRATEGIES.include?(new_strategy)
      PseudoCleaner::Logger.write "*** Unknown/invalid cleaning strategy #{test_example.metadata[:strategy]}.  Using default: :transaction ***".red.on_light_white
      new_strategy = :transaction
    end
    if test_example.metadata[:js]
      new_strategy ||= :pseudo_delete
      new_strategy = :pseudo_delete if new_strategy == :transaction
    end
    new_strategy ||= :transaction

    PseudoCleaner::MasterCleaner.start_example(test_example, new_strategy)
  end

  config.after(:each) do |example|
    test_example = example
    test_example = example.example if example.respond_to?(:example)

    PseudoCleaner::MasterCleaner.end_example(test_example)
  end
end