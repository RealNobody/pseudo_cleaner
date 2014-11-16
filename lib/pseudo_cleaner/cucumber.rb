first_test_run                                     = false

# turn off Cucumber's default usage of DatabaseCleaner
Cucumber::Rails::Database.autorun_database_cleaner = false

Before do |scenario|
  unless first_test_run
    first_test_run = true
    # before tests run...
    # We start suite in case a custom cleaner wants/needs to.
    if PseudoCleaner::Configuration.current_instance.clean_database_before_tests
      PseudoCleaner::MasterCleaner.reset_database
    else
      PseudoCleaner::MasterCleaner.start_suite
    end

    DatabaseCleaner.strategy = :transaction
  end
end

Before("~@truncation", "~@deletion") do |scenario|
  PseudoCleaner::MasterCleaner.start_example(scenario, :pseudo_delete)
end

Before("@truncation") do |scenario|
  PseudoCleaner::MasterCleaner.start_example(scenario, :truncation)
end

Before("@deletion", "~@truncation") do |scenario|
  PseudoCleaner::MasterCleaner.start_example(scenario, :deletion)
end

Before("@none") do |scenario|
  PseudoCleaner::MasterCleaner.start_example(scenario, :none)
end

After do |scenario|
  PseudoCleaner::MasterCleaner.end_example(scenario)
end

at_exit do
  # We end suite in case a custom cleaner wants/needs to.
  PseudoCleaner::MasterCleaner.end_suite
end