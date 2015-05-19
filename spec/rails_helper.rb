require "spec_helper"

require "faker"
require "cornucopia"
require "cornucopia/rspec_hooks"

Cornucopia::Util::Configuration.auto_open_report_after_generation(ENV['RM_INFO'])

# Cornucopia::Util::Configuration.seed         = 1
# Cornucopia::Util::Configuration.context_seed = 1