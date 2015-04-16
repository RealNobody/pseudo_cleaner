first_test_run = false

# I haven't tested this fully yet, but I think that this should work.

Spinach.hooks.around_scenario do |scenario_data, step_definitions, &block|
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

  strategy = if scenario_data.tags.include?("@none")
               :none
             elsif scenario_data.tags.include?("@truncation")
               :truncation
             elsif scenario_data.tags.include?("@deletion")
               :deletion
             else
               :pseudo_delete
             end
  PseudoCleaner::MasterCleaner.start_example(scenario_data, strategy)

  begin
    block.call
  ensure
    PseudoCleaner::MasterCleaner.end_example(scenario_data)
  end
end

Spinach.hooks.after_run do |status|
  # We end suite in case a custom cleaner wants/needs to.
  PseudoCleaner::MasterCleaner.end_suite
end