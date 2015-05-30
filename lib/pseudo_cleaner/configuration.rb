require "singleton"

module PseudoCleaner
  class Configuration
    include Singleton

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
    attr_accessor :db_connections
    attr_accessor :peek_data_on_error
    attr_accessor :peek_data_not_on_error
    attr_accessor :enable_full_data_dump_tag
    attr_accessor :disable_cornucopia_output
    attr_accessor :benchmark

    def self.current_instance
      self.instance
    end

    def initialize
      @output_diagnostics          = false # false to keep the noise level down...
      @clean_database_before_tests = false # false because I think it will annoy developers...
      @reset_auto_increment        = true # true because I think it should be done
      @single_cleaner_set          = true # true because I hope it will improve performance
      @post_transaction_analysis   = false # should only be set true if you are searching for a problem
      @db_connections              = {}
      @peek_data_on_error          = true
      @peek_data_not_on_error      = false
      @enable_full_data_dump_tag   = true
      @disable_cornucopia_output   = false
      @benchmark                   = false
    end

    # Backwards comaptibility...
    def self.db_connection=(connection)
      self.instance.db_connection = connection
    end

    def self.db_connection(type)
      self.instance.db_connection(type)
    end

    def db_connection=(connection)
      if Object.const_defined?("ActiveRecord", false) && ActiveRecord.const_defined?("Base", false)
        table_is_active_record = connection == ActiveRecord::Base
        table_super_class      = connection.superclass if connection
        while !table_is_active_record && table_super_class
          table_is_active_record = (table_super_class == ActiveRecord::Base)
          table_super_class      = table_super_class.superclass
        end

        @db_connections[:active_record] = connection if table_is_active_record
      end

      if Object.const_defined?("Sequel", false) && Sequel.const_defined?("Model", false)
        @db_connections[:sequel] = connection
      end
    end

    def db_connection(type)
      if (!type)
        if Object.const_defined?("Sequel", false) && Sequel.const_defined?("Model", false)
          type = :sequel
        else
          type = :active_record
        end
      end

      if type == :sequel
        @db_connections[type] ||= Sequel::DATABASES[0]
      else
        @db_connections[type] ||= ActiveRecord::Base
      end

      @db_connections[type]
    end
  end
end