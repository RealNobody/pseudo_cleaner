require "singleton"

first_test_run = false

# I haven't tested this fully yet, but I think that this should work.

module PseudoCleaner
  class SpinachErrorHandler
    attr_accessor :exception

    include Singleton
  end
end

Spinach.hooks.around_scenario do |scenario_data, step_definitions, &block|
  PseudoCleaner::SpinachErrorHandler.exception = nil

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

  report_name = "#{scenario_data.feature.name} : #{scenario_data.name}"
  strategy    = if scenario_data.tags.include?("@none")
                  :none
                elsif scenario_data.tags.include?("@truncation")
                  :truncation
                elsif scenario_data.tags.include?("@deletion")
                  :deletion
                else
                  :pseudo_delete
                end
  PseudoCleaner::MasterCleaner.start_example(scenario_data,
                                             strategy,
                                             description: "PseudoCleaner::start_test - #{report_name}")

  begin
    block.call
  ensure
    if scenario_data.tags.include?("@full_data_dump")
      if PseudoCleaner::SpinachErrorHandler.exception
        if PseudoCleaner::Configuration.instance.enable_full_data_dump_tag ||
            PseudoCleaner::Configuration.instance.peek_data_on_error
          PseudoCleaner::MasterCleaner.peek_data_inline(description: "PseudoCleaner::peek_data - #{report_name}")
        end
      else
        if PseudoCleaner::Configuration.instance.enable_full_data_dump_tag ||
            PseudoCleaner::Configuration.instance.peek_data_not_on_error
          PseudoCleaner::MasterCleaner.peek_data_new_test(description: "PseudoCleaner::peek_data - #{report_name}")
        end
      end
    else
      if PseudoCleaner::SpinachErrorHandler.exception
        if PseudoCleaner::Configuration.instance.peek_data_on_error
          PseudoCleaner::MasterCleaner.peek_data_inline(description: "PseudoCleaner::peek_data - #{report_name}")
        end
      else
        if PseudoCleaner::Configuration.instance.peek_data_not_on_error
          PseudoCleaner::MasterCleaner.peek_data_new_test(description: "PseudoCleaner::peek_data - #{report_name}")
        end
      end
    end

    PseudoCleaner::MasterCleaner.end_example(scenario_data,
                                             description: "PseudoCleaner::end_test - #{report_name}")
    PseudoCleaner::SpinachErrorHandler.exception = nil
  end
end

Spinach.hooks.on_failed_step do |step_data, exception, location, step_definitions|
  PseudoCleaner::SpinachErrorHandler.exception = exception
end

Spinach.hooks.on_error_step do |step_data, exception, location, step_definitions|
  PseudoCleaner::SpinachErrorHandler.exception = exception
end

Spinach.hooks.after_run do |status|
  # We end suite in case a custom cleaner wants/needs to.
  PseudoCleaner::MasterCleaner.end_suite
end