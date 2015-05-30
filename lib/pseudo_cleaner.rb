require "benchmark"

time = Benchmark.measure do
  require "sorted_seeder"
  require "colorize"
  require "database_cleaner"
  require "pseudo_cleaner/version"
  require "pseudo_cleaner/configuration"
  require "pseudo_cleaner/table_cleaner"
  require "pseudo_cleaner/master_cleaner"
  require "pseudo_cleaner/logger"
end
puts "PseudoCleaner load time: #{time}"

module PseudoCleaner
  # Your code goes here...
end