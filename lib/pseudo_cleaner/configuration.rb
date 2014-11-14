module PseudoCleaner
  class Configuration
    @@current_instance = nil

    # A simple configuration class for the PseudoCleaner
    #
    # Configurations:
    #   output_diagnostics  - true/false
    #                         if true, the system will use puts to output information about what it is doing...
    attr_accessor :output_diagnostics
    attr_accessor :clean_database_before_tests
    attr_accessor :reset_auto_increment
    attr_accessor :single_cleaner_set

    def self.current_instance
      @@current_instance ||= PseudoCleaner::Configuration.new
    end

    def initialize
      @output_diagnostics = false
      @clean_database_before_tests = false
      @reset_auto_increment = false
      @single_cleaner_set = true
    end

    #todo add configuration for doing referential integrity checks after run
    #todo add configuration for fixing referential integrity failures after run
    #todo add configuration for raising error if referential integrity is bad before the test runs
  end
end