require "redis"
require "redis-namespace"
require "pseudo_cleaner/master_cleaner"
require "pseudo_cleaner/configuration"
require "pseudo_cleaner/logger"
require "colorize"

module PseudoCleaner
  ##
  # This class "cleans" a single redis connection.
  #
  # The cleaning is done by opening a monitor connection on redis and monitoring it for any actions that change values
  # in redis.
  #
  # Long term, I was thinking about keeping some stats on the redis calls, but for now, I'm not.
  #
  # The cleaner roughly works as follows:
  #   * Get a list of all existing keys in the database as a level starting point.
  #   * Start a monitor
  #     * The monitor records any key that is updated or changed
  #   * When a test ends
  #     * Ask the monitor for a list of all changed keys.
  #     * The monitor resets the list of all changed keys.
  #   * When the suite ends
  #     * Get a list of all of the keys
  #     * Compare that list to the starting level
  #
  # Again, like the TableCleaner, if items are updated, this won't be able to "fix" that, but it will report on it.
  #
  # At this time, my code only pays attention to one database.  It ignores other databases.  We could extend things
  # and have the monitor watch multiple databases.  I'll have to do that later if I find a need.

  # NOTE: Like the database cleaner, if the test is interrupted and test_end isn't called, the redis database may be
  #       left in an uncertain state.

  # I'm not a huge fan of sleeps.  In the non-rails world, I used to be able to do a sleep(0) to signal the system to
  # check if somebody else needed to do some work.  Testing with Rails, I find I have to actually sleep, so I do a
  # very short time like 0.01.
  class RedisCleaner
    FLUSH_COMMANDS =
        [
            "flushall",
            "flushdb"
        ]
    SET_COMMANDS   =
        [
            "sadd",
            "zadd",
            "srem",
            "zrem",
            "zremrangebyrank",
            "zremrangebyscore"
        ]
    WRITE_COMMANDS =
        [
            "append",
            "bitop",
            "blpop",
            "brpop",
            "brpoplpush",
            "decr",
            "decrby",
            "del",
            "expire",
            "expireat",
            "getset",
            "hset",
            "hsetnx",
            "hincrby",
            "hincrbyfloat",
            "hmset",
            "hdel",
            "incr",
            "incrby",
            "incrbyfloat",
            "linsert",
            "lpop",
            "lpush",
            "lpushx",
            "lrem",
            "lset",
            "ltrim",
            "mapped_hmset",
            "mapped_mset",
            "mapped_msetnx",
            "move",
            "mset",
            "msetnx",
            "persist",
            "pexpire",
            "pexpireat",
            "psetex",
            "rename",
            "renamenx",
            "restore",
            "rpop",
            "rpoplpush",
            "rpush",
            "rpushx",
            "sdiffstore",
            "set",
            "setbit",
            "setex",
            "setnx",
            "setrange",
            "sinterstore",
            "smove",
            "sort",
            "spop",
            "sunionstore",
            "zincrby",
            "zinterstore",
            "[]=",
        ]
    READ_COMMANDS  =
        [
            "bitcount",
            "bitop",
            "dump",
            "exists",
            "get",
            "getbit",
            "getrange",
            "hget",
            "hmget",
            "hexists",
            "hlen",
            "hkeys",
            "hscan",
            "hscan_each",
            "hvals",
            "hgetall",
            "lindex",
            "llen",
            "lrange",
            "mapped_hmget",
            "mapped_mget",
            "mget",
            "persist",
            "scard",
            "scan",
            "scan_each",
            "sdiff",
            "sismember",
            "smembers",
            "srandmember",
            "sscan",
            "sscan_each",
            "strlen",
            "sunion",
            "type",
            "zcard",
            "zcount",
            "zrange",
            "zrangebyscore",
            "zrank",
            "zrevrange",
            "zrevrangebyscore",
            "zrevrank",
            "zscan",
            "zscan_each",
            "zscore",
            "[]",
        ]

    attr_reader :initial_keys
    attr_accessor :options

    def initialize(start_method, end_method, table, options)
      @initial_keys       = SortedSet.new
      @monitor_thread     = nil
      @redis_name         = nil
      @suite_altered_keys = SortedSet.new
      @updated_keys       = SortedSet.new
      @multi_commands     = []
      @in_multi           = false
      @in_redis_cleanup   = false
      @suspend_tracking   = false

      unless PseudoCleaner::MasterCleaner::VALID_START_METHODS.include?(start_method)
        raise "You must specify a valid start function from: #{PseudoCleaner::MasterCleaner::VALID_START_METHODS}."
      end
      unless PseudoCleaner::MasterCleaner::VALID_END_METHODS.include?(end_method)
        raise "You must specify a valid end function from: #{PseudoCleaner::MasterCleaner::VALID_END_METHODS}."
      end

      @options = options

      @options[:table_start_method] ||= start_method
      @options[:table_end_method]   ||= end_method
      @options[:output_diagnostics] ||= PseudoCleaner::Configuration.current_instance.output_diagnostics ||
          PseudoCleaner::Configuration.current_instance.post_transaction_analysis

      @redis = table
    end

    # Ruby defines a now deprecated type method so we need to override it here
    # since it will never hit method_missing
    def type(key)
      redis.type(key)
    end

    alias_method :self_respond_to?, :respond_to?

    # emulate Ruby 1.9+ and keep respond_to_missing? logic together.
    def respond_to?(command, include_private=false)
      super or respond_to_missing?(command, include_private)
    end

    def updated_keys
      @updated_keys ||= SortedSet.new
    end

    def method_missing(command, *args, &block)
      normalized_command = command.to_s.downcase

      if redis.respond_to?(normalized_command)
        if (normalized_command == "pipelined" ||
            (normalized_command == "multi" && block)) &&
            !@suspend_tracking
          @in_multi          = true
          normalized_command = "exec"
        end

        response = redis.send(command, *args, &block)

        if @in_multi && !(["exec", "discard"].include?(normalized_command))
          @multi_commands << [normalized_command, *args]
        else
          process_command(response, normalized_command, *args)
        end

        response
      else
        super
      end
    end

    def process_command(response, *args)
      unless @in_redis_cleanup || @suspend_tracking
        if "multi" == args[0]
          @in_multi       = true
          @multi_commands = []
        elsif ["exec", "pipelined"].include?(args[0])
          begin
            if (!response && @multi_commands.length > 0) || (response && response.length != @multi_commands.length)
              puts "exec response does not match sent commands.\n  response: #{response}\n  commands: #{@multi_commands}"

              # make the response length match the commands length.
              # so far the only time this has happened was when a multi returned nil which SHOULD indicate a failure
              #
              # I am assuming that the multi failed in this case, but even if so, it is safest for tracking purposes
              # to assume that redis DID change and record it as such.  Even if I am wrong, for the cleaner, it
              # doesn't matter, and there is no harm.
              response ||= []
              @multi_commands.each_with_index do |command, index|
                if response.length < index
                  response << true
                end
              end
            end

            @multi_commands.each_with_index do |command, index|
              process_command(response[index], *command)
            end
          ensure
            @in_multi       = false
            @multi_commands = []
          end
        elsif "discard" == args[0]
          @in_multi       = false
          @multi_commands = []
        elsif WRITE_COMMANDS.include?(args[0])
          updated_keys.merge(extract_keys(*args))
        elsif SET_COMMANDS.include?(args[0])
          update_key = true
          if [true, false].include?(response)
            update_key = response
          else
            update_key = response > 0 rescue true
          end

          if update_key
            updated_keys.merge(extract_keys(*args))
          end
        end
      end
    end

    def respond_to_missing?(command, include_all=false)
      return true if WRITE_COMMANDS.include?(command.to_s.downcase)

      # blind passthrough is deprecated and will be removed in 2.0
      if redis.respond_to?(command, include_all)
        return true
      end

      defined?(super) && super
    end

    def extract_keys(command, *args)
      handling     = Redis::Namespace::COMMANDS[command.to_s.downcase]
      message_keys = []

      (before, after) = handling

      case before
        when :first
          message_keys << args[0] if args[0]

        when :all
          args.each do |arg|
            message_keys << arg
          end

        when :exclude_first
          args.each do |arg|
            message_keys << arg
          end
          message_keys.shift

        when :exclude_last
          args.each do |arg|
            message_keys << arg
          end
          message_keys.pop unless message_keys.length == 1

        when :exclude_options
          args.each do |arg|
            message_keys << arg unless arg.is_a?(Hash)
          end

        when :alternate
          args.each_with_index do |arg, i|
            message_keys << arg if i.even?
          end

        when :sort
          if args[-1].is_a?(Hash)
            if args[1][:store]
              message_keys << args[1][:store]
            end
          end

        # when :eval_style
        #
        # when :scan_style
      end

      message_keys
    end

    def <=>(right_object)
      if (right_object.is_a?(PseudoCleaner::RedisCleaner))
        return 0
      elsif (right_object.is_a?(PseudoCleaner::TableCleaner))
        return 1
      else
        if right_object.respond_to?(:<=>)
          comparison = (right_object <=> self)
          if comparison
            return -1 * comparison
          end
        end
      end

      return 1
    end

    def redis
      @redis ||= Redis.current
    end

    def suite_start test_strategy
      time = Benchmark.measure do
        puts "  RedisCleaner(#{redis_name})" if PseudoCleaner::Configuration.instance.benchmark

        @test_strategy ||= test_strategy

        start_monitor
      end

      puts "  RedisCleaner(#{redis_name}) time: #{time}" if PseudoCleaner::Configuration.instance.benchmark
    end

    def suspend_tracking(&block)
      begin
        @suspend_tracking = true

        block.yield
      ensure
        @suspend_tracking = false
      end
    end

    def test_start test_strategy
      @test_strategy ||= test_strategy

      time = Benchmark.measure do
        puts "  RedisCleaner(#{redis_name})" if PseudoCleaner::Configuration.instance.benchmark

        synchronize_test_values do |test_values|
          if test_values && !test_values.empty?
            report_dirty_values "values altered before the test started", test_values

            test_values.each do |value|
              redis.del value unless initial_keys.include?(value)
            end
          end
        end

        @updated_keys = SortedSet.new
      end

      puts "  RedisCleaner(#{redis_name}) time: #{time}" if PseudoCleaner::Configuration.instance.benchmark
    end

    def test_end test_strategy
      time = Benchmark.measure do
        puts "  RedisCleaner(#{redis_name})" if PseudoCleaner::Configuration.instance.benchmark

        synchronize_test_values do |updated_values|
          if updated_values && !updated_values.empty?
            report_keys = []

            if @options[:output_diagnostics]
              report_dirty_values "updated values", updated_values
            end

            updated_values.each do |value|
              if initial_keys.include?(value)
                report_keys << value
                @suite_altered_keys << value unless ignore_key(value)
              else
                redis.del(value)
              end
            end

            report_dirty_values "initial values altered by test", report_keys
          end
        end

        @updated_keys = SortedSet.new
      end

      puts "  RedisCleaner(#{redis_name}) time: #{time}" if PseudoCleaner::Configuration.instance.benchmark
    end

    def suite_end test_strategy
      time = Benchmark.measure do
        puts "  RedisCleaner(#{redis_name})" if PseudoCleaner::Configuration.instance.benchmark

        report_end_of_suite_state "suite end"
      end

      puts "  RedisCleaner(#{redis_name}) time: #{time}" if PseudoCleaner::Configuration.instance.benchmark
    end

    def reset_suite
      time = Benchmark.measure do
        puts "  RedisCleaner(#{redis_name})" if PseudoCleaner::Configuration.instance.benchmark

        report_end_of_suite_state "reset suite"

        start_monitor
      end

      puts "  RedisCleaner(#{redis_name}) time: #{time}" if PseudoCleaner::Configuration.instance.benchmark
    end

    def ignore_regexes
      []
    end

    def ignore_key(key)
      ignore_regexes.detect { |ignore_regex| key =~ ignore_regex }
    end

    def redis_name
      unless @redis_name
        redis_options = redis.client.options.with_indifferent_access
        @redis_name   = "#{redis_options[:host]}:#{redis_options[:port]}/#{redis_options[:db]}"
      end

      @redis_name
    end

    def review_rows(&block)
      time = Benchmark.measure do
        puts "  RedisCleaner(#{redis_name})" if PseudoCleaner::Configuration.instance.benchmark

        synchronize_test_values do |updated_values|
          if updated_values && !updated_values.empty?
            updated_values.each do |updated_value|
              unless ignore_key(updated_value)
                block.yield redis_name, report_record(updated_value)
              end
            end
          end
        end
      end

      puts "  RedisCleaner(#{redis_name}) time: #{time}" if PseudoCleaner::Configuration.instance.benchmark
    end

    def peek_values
      time = Benchmark.measure do
        puts "  RedisCleaner(#{redis_name})" if PseudoCleaner::Configuration.instance.benchmark

        synchronize_test_values do |updated_values|
          if updated_values && !updated_values.empty?
            output_values = false

            if PseudoCleaner::MasterCleaner.report_table
              Cornucopia::Util::ReportTable.new(nested_table:         PseudoCleaner::MasterCleaner.report_table,
                                                nested_table_label:   redis_name,
                                                suppress_blank_table: true) do |report_table|
                updated_values.each_with_index do |updated_value, index|
                  unless ignore_key(updated_value)
                    output_values = true
                    report_table.write_stats index.to_s, report_record(updated_value)
                  end
                end
              end
            else
              PseudoCleaner::Logger.write("  #{redis_name}")

              updated_values.each_with_index do |updated_value, index|
                unless ignore_key(updated_value)
                  output_values = true
                  PseudoCleaner::Logger.write("    #{index}: #{report_record(updated_value)}")
                end
              end
            end

            PseudoCleaner::MasterCleaner.report_error if output_values
          end
        end
      end

      puts "  RedisCleaner(#{redis_name}) time: #{time}" if PseudoCleaner::Configuration.instance.benchmark
    end

    def report_end_of_suite_state report_reason
      current_keys = SortedSet.new(redis.keys)

      deleted_keys = initial_keys - current_keys
      new_keys     = current_keys - initial_keys

      # filter out values we inserted that will go away on their own.
      new_keys     = new_keys.select { |key| (key =~ /redis_cleaner::synchronization_(?:end_)?key_[0-9]+_[0-9]+/).nil? }

      report_dirty_values "new values as of #{report_reason}", new_keys
      report_dirty_values "values deleted before #{report_reason}", deleted_keys
      report_dirty_values "initial values changed during suite run", @suite_altered_keys

      @suite_altered_keys = SortedSet.new

      new_keys.each do |key_value|
        redis.del key_value
      end
    end

    def synchronize_test_values(&block)
      if @in_multi
        # Ideally we should never get here, but if we do, assume everything was changed and keep moving...
        @multi_commands.each do |args|
          if WRITE_COMMANDS.include?(args[0])
            updated_keys.merge(extract_keys(*args))
          elsif SET_COMMANDS.include?(args[0])
            updated_keys.merge(extract_keys(*args))
          end
        end

        @in_multi       = false
        @multi_commands = []
      end

      updated_values = updated_keys.dup

      @in_redis_cleanup = true

      begin
        block.yield updated_values
      ensure
        @in_redis_cleanup = false
      end
    end

    def start_monitor
      cleaner_class = self

      @initial_keys = SortedSet.new(redis.keys)

      if @options[:output_diagnostics]
        if PseudoCleaner::MasterCleaner.report_table
          Cornucopia::Util::ReportTable.new(nested_table:         PseudoCleaner::MasterCleaner.report_table,
                                            nested_table_label:   redis_name,
                                            suppress_blank_table: true) do |report_table|
            report_table.write_stats "initial keys count", @initial_keys.count
          end
        else
          PseudoCleaner::Logger.write("#{redis_name}")
          PseudoCleaner::Logger.write("    Initial keys count - #{@initial_keys.count}")
        end
      end
    end

    def report_record(key_name)
      key_hash = { key: key_name, type: redis.type(key_name), ttl: redis.ttl(key_name) }
      case key_hash[:type]
        when "string"
          key_hash[:value] = redis.get(key_name)
        when "list"
          key_hash[:list] = { len: redis.llen(key_name), values: redis.lrange(key_name, 0, -1) }
        when "set"
          key_hash[:set] = redis.smembers(key_name)
        when "zset"
          key_hash[:sorted_set] = redis.smembers(key_name)
        when "hash"
          key_hash[:list] = { len: redis.hlen(key_name), values: redis.hgetall(key_name) }
      end

      if key_hash[:value].nil? &&
          key_hash[:list].nil? &&
          key_hash[:set].nil? &&
          key_hash[:sorted_set].nil? &&
          key_hash[:hash].nil?
        key_hash[:value] = "[[DELETED]]"
      end

      key_hash
    end

    def report_dirty_values message, test_values
      if test_values && !test_values.empty?
        output_values = false

        if PseudoCleaner::MasterCleaner.report_table
          Cornucopia::Util::ReportTable.new(nested_table:         PseudoCleaner::MasterCleaner.report_table,
                                            nested_table_label:   redis_name,
                                            suppress_blank_table: true) do |report_table|
            report_table.write_stats "action", message
            test_values.each_with_index do |key_name, index|
              unless ignore_key(key_name)
                output_values = true
                report_table.write_stats index, report_record(key_name)
              end
            end
          end
        else
          PseudoCleaner::Logger.write("********* RedisCleaner - #{message}".red.on_light_white)
          test_values.each do |key_name|
            unless ignore_key(key_name)
              output_values = true
              PseudoCleaner::Logger.write("  #{key_name}: #{report_record(key_name)}".red.on_light_white)
            end
          end
        end

        PseudoCleaner::MasterCleaner.report_error if output_values
      end
    end
  end
end