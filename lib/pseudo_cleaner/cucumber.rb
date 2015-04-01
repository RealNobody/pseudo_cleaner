require "singleton"

# turn off Cucumber's default usage of DatabaseCleaner
Cucumber::Rails::Database.autorun_database_cleaner = false

class CucumberHook
  include Singleton

  attr_accessor :first_test_run

  def initialize
    @first_test_run = false
  end

  def run_test(scenario, strategy, block)
    unless first_test_run
      @first_test_run = true
      # before tests run...
      # We start suite in case a custom cleaner wants/needs to.

      if PseudoCleaner::Configuration.current_instance.clean_database_before_tests
        PseudoCleaner::MasterCleaner.reset_database
      else
        PseudoCleaner::MasterCleaner.start_suite
      end

      DatabaseCleaner.strategy = :transaction
    end

    PseudoCleaner::MasterCleaner.start_example(scenario, strategy)

    begin
      block.call
    ensure
      PseudoCleaner::MasterCleaner.end_example(scenario)
    end
  end
end

Around("~@truncation", "~@deletion") do |scenario, block|
  CucumberHook.instance.run_test(scenario, :pseudo_delete, block)
end

Around("@truncation") do |scenario, block|
  CucumberHook.instance.run_test(scenario, :truncation, block)
end

Around("@deletion", "~@truncation") do |scenario, block|
  CucumberHook.instance.run_test(scenario, :deletion, block)
end

Around("@none") do |scenario, block|
  CucumberHook.instance.run_test(scenario, :none, block)
end

at_exit do
  # We end suite in case a custom cleaner wants/needs to.
  PseudoCleaner::MasterCleaner.end_suite
end