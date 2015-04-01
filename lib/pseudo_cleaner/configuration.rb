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
    attr_accessor :post_transaction_analysis

    def self.current_instance
      @@current_instance ||= PseudoCleaner::Configuration.new
    end

    def initialize
      @output_diagnostics          = false  # false to keep the noise level down...
      @clean_database_before_tests = false  # false because I think it will annoy developers...
      @reset_auto_increment        = true   # true because I think it should be done
      @single_cleaner_set          = true   # true because I hope it will improve performance
      @post_transaction_analysis   = false  # should only be set true if you are searching for a problem
    end

    def self.db_connection=(connection)
      @db_connection = connection
    end

    def self.db_connection(type)
      if @db_connection || type.nil?
        @db_connection
      else
        if type == :sequel
          Sequel::DATABASES[0]
        else
          ActiveRecord::Base
        end
      end
    end
  end
end