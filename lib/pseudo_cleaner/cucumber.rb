require "singleton"

# turn off Cucumber's default usage of DatabaseCleaner
Cucumber::Rails::Database.autorun_database_cleaner = false

AfterConfiguration do |config|
  CucumberHook.instance.init_pseudo
end

class CucumberHook
  include Singleton

  attr_accessor :first_test_run

  def initialize
    @first_test_run = false
  end

  def init_pseudo
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
  end

  def start_test(scenario, strategy)
    PseudoCleaner::MasterCleaner.start_example(scenario,
                                               strategy,
                                               description: "PseudoCleaner::start_test - #{report_name(scenario)}",
                                               location:    test_location(scenario))
  end

  def end_test(scenario)
    PseudoCleaner::MasterCleaner.end_example(scenario,
                                             description: "PseudoCleaner::end_test - #{report_name (scenario)}",
                                             location:    test_location(scenario))
  end

  def test_location(scenario)
    if scenario.respond_to?(:feature)
      "#{scenario.location.file}:#{scenario.location.line}"
    elsif scenario.respond_to?(:scenario_outline)
      "#{scenario.scenario_outline.instance_variable_get(:@example_sections)[0][0][0].file}:#{scenario.scenario_outline.instance_variable_get(:@example_sections)[0][0][0].line}"
    end
  end

  def report_name(scenario)
    report_name = "Unknown"
    if scenario.respond_to?(:feature)
      report_name = "#{scenario.feature.title}:#{scenario.title}"
    elsif scenario.respond_to?(:line)
      report_name = "Line - #{scenario.line}"
    end
  end

  def run_test(scenario, strategy, block)
    start_test(scenario, strategy)

    begin
      block.call
    ensure
      end_test(scenario)
    end
  end

  def peek_data_inline(scenario)
    PseudoCleaner::MasterCleaner.peek_data_inline(description: "PseudoCleaner::peek_data - #{report_name(scenario)}",
                                                  location:    test_location(scenario))
  end

  def peek_data_new_test(scenario)
    PseudoCleaner::MasterCleaner.peek_data_new_test(description: "PseudoCleaner::peek_data - #{report_name(scenario)}",
                                                    location:    test_location(scenario))
  end
end

##
#  Most testing systems do tests as:
#   * Around
#   *   Before
#   *   After
#
# Cucumber doesn't.  It does it:
#   * Before
#   * Around
#   * After
#
# What is more, it is WAY worse than that.
#
# If your Feature has a Background block:
#     Feature my feature
#
#     Background
#     Scenario
#
# Then the Before happens before the Background whereas the Around is only around the
# Scenario part of the feature.
#
# I hope that this gets fixed, but until it does, we can't use Around for database cleaning.
#
# This was fixed in Cucumber 2.0.


if Cucumber::VERSION.split[0].to_i >= 2
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
else
  Before("~@truncation", "~@deletion") do |scenario|
    CucumberHook.instance.start_test(scenario, :pseudo_delete)
  end

  Before("@truncation") do |scenario|
    CucumberHook.instance.start_test(scenario, :truncation)
  end

  Before("@deletion", "~@truncation") do |scenario|
    CucumberHook.instance.start_test(scenario, :deletion)
  end

  Before("@none") do |scenario|
    CucumberHook.instance.start_test(scenario, :none)
  end

  After do |scenario|
    CucumberHook.instance.end_test(scenario)
  end
end

After("~@full_data_dump") do |scenario|
  if scenario.failed?
    if PseudoCleaner::Configuration.instance.peek_data_on_error
      CucumberHook.instance.peek_data_inline(scenario)
    end
  else
    if PseudoCleaner::Configuration.instance.peek_data_not_on_error
      CucumberHook.instance.peek_data_new_test(scenario)
    end
  end
end

After("@full_data_dump") do |scenario|
  if scenario.failed?
    if PseudoCleaner::Configuration.instance.enable_full_data_dump_tag ||
        PseudoCleaner::Configuration.instance.peek_data_on_error
      CucumberHook.instance.peek_data_inline(scenario)
    end
  else
    if PseudoCleaner::Configuration.instance.enable_full_data_dump_tag ||
        PseudoCleaner::Configuration.instance.peek_data_not_on_error
      CucumberHook.instance.peek_data_new_test(scenario)
    end
  end
end

at_exit do
  # We end suite in case a custom cleaner wants/needs to.
  PseudoCleaner::MasterCleaner.end_suite
end