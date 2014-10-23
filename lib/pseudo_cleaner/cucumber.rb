if true
  # before tests run...
  PseudoCleaner::MasterCleaner.reset_database

  # We start suite in case a custom cleaner wants/needs to.
  DatabaseCleaner.strategy = :transaction
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