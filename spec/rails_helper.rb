require "spec_helper"

require "faker"
require "cornucopia"
require "cornucopia/rspec_hooks"

Dir[File.join(File.dirname(__FILE__), "shared_examples", "**", "*.rb")].each { |file_name| require file_name }

Cornucopia::Util::Configuration.auto_open_report_after_generation(ENV['RM_INFO'])

# Cornucopia::Util::Configuration.seed         = 1
# Cornucopia::Util::Configuration.context_seed = 1
# Cornucopia::Util::Configuration.order_seed   = 1