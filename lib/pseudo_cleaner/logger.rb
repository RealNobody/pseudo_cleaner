module PseudoCleaner
  class Logger
    class << self
      def write(log_output)
        puts(log_output)
      end
    end
  end
end