require "redis"
# require "redis-namespace"
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
    # copied from Redis::Namespace
    COMMANDS = {
        "append"           => [:first],
        "auth"             => [],
        "bgrewriteaof"     => [],
        "bgsave"           => [],
        "bitcount"         => [:first],
        "bitop"            => [:exclude_first],
        "blpop"            => [:exclude_last, :first],
        "brpop"            => [:exclude_last, :first],
        "brpoplpush"       => [:exclude_last],
        "config"           => [],
        "dbsize"           => [],
        "debug"            => [:exclude_first],
        "decr"             => [:first],
        "decrby"           => [:first],
        "del"              => [:all],
        "discard"          => [],
        "disconnect!"      => [],
        "dump"             => [:first],
        "echo"             => [],
        "exists"           => [:first],
        "expire"           => [:first],
        "expireat"         => [:first],
        "eval"             => [:eval_style],
        "evalsha"          => [:eval_style],
        "exec"             => [],
        "flushall"         => [],
        "flushdb"          => [],
        "get"              => [:first],
        "getbit"           => [:first],
        "getrange"         => [:first],
        "getset"           => [:first],
        "hset"             => [:first],
        "hsetnx"           => [:first],
        "hget"             => [:first],
        "hincrby"          => [:first],
        "hincrbyfloat"     => [:first],
        "hmget"            => [:first],
        "hmset"            => [:first],
        "hdel"             => [:first],
        "hexists"          => [:first],
        "hlen"             => [:first],
        "hkeys"            => [:first],
        "hscan"            => [:first],
        "hscan_each"       => [:first],
        "hvals"            => [:first],
        "hgetall"          => [:first],
        "incr"             => [:first],
        "incrby"           => [:first],
        "incrbyfloat"      => [:first],
        "info"             => [],
        "keys"             => [:first, :all],
        "lastsave"         => [],
        "lindex"           => [:first],
        "linsert"          => [:first],
        "llen"             => [:first],
        "lpop"             => [:first],
        "lpush"            => [:first],
        "lpushx"           => [:first],
        "lrange"           => [:first],
        "lrem"             => [:first],
        "lset"             => [:first],
        "ltrim"            => [:first],
        "mapped_hmset"     => [:first],
        "mapped_hmget"     => [:first],
        "mapped_mget"      => [:all, :all],
        "mapped_mset"      => [:all],
        "mapped_msetnx"    => [:all],
        "mget"             => [:all],
        "monitor"          => [:monitor],
        "move"             => [:first],
        "multi"            => [],
        "mset"             => [:alternate],
        "msetnx"           => [:alternate],
        "object"           => [:exclude_first],
        "persist"          => [:first],
        "pexpire"          => [:first],
        "pexpireat"        => [:first],
        "pfadd"            => [:first],
        "pfcount"          => [:all],
        "pfmerge"          => [:all],
        "ping"             => [],
        "psetex"           => [:first],
        "psubscribe"       => [:all],
        "pttl"             => [:first],
        "publish"          => [:first],
        "punsubscribe"     => [:all],
        "quit"             => [],
        "randomkey"        => [],
        "rename"           => [:all],
        "renamenx"         => [:all],
        "restore"          => [:first],
        "rpop"             => [:first],
        "rpoplpush"        => [:all],
        "rpush"            => [:first],
        "rpushx"           => [:first],
        "sadd"             => [:first],
        "save"             => [],
        "scard"            => [:first],
        "scan"             => [:scan_style, :second],
        "scan_each"        => [:scan_style, :all],
        "script"           => [],
        "sdiff"            => [:all],
        "sdiffstore"       => [:all],
        "select"           => [],
        "set"              => [:first],
        "setbit"           => [:first],
        "setex"            => [:first],
        "setnx"            => [:first],
        "setrange"         => [:first],
        "shutdown"         => [],
        "sinter"           => [:all],
        "sinterstore"      => [:all],
        "sismember"        => [:first],
        "slaveof"          => [],
        "smembers"         => [:first],
        "smove"            => [:exclude_last],
        "sort"             => [:sort],
        "spop"             => [:first],
        "srandmember"      => [:first],
        "srem"             => [:first],
        "sscan"            => [:first],
        "sscan_each"       => [:first],
        "strlen"           => [:first],
        "subscribe"        => [:all],
        "sunion"           => [:all],
        "sunionstore"      => [:all],
        "ttl"              => [:first],
        "type"             => [:first],
        "unsubscribe"      => [:all],
        "unwatch"          => [:all],
        "watch"            => [:all],
        "zadd"             => [:first],
        "zcard"            => [:first],
        "zcount"           => [:first],
        "zincrby"          => [:first],
        "zinterstore"      => [:exclude_options],
        "zrange"           => [:first],
        "zrangebylex"      => [:first],
        "zrangebyscore"    => [:first],
        "zrank"            => [:first],
        "zrem"             => [:first],
        "zremrangebyrank"  => [:first],
        "zremrangebyscore" => [:first],
        "zremrangebylex"   => [:first],
        "zrevrange"        => [:first],
        "zrevrangebyscore" => [:first],
        "zrevrangebylex"   => [:first],
        "zrevrank"         => [:first],
        "zscan"            => [:first],
        "zscan_each"       => [:first],
        "zscore"           => [:first],
        "zunionstore"      => [:exclude_options],
        "[]"               => [:first],
        "[]="              => [:first]
    }

    FLUSH_COMMANDS       =
        [
            "flushall",
            "flushdb"
        ]
    NUM_CHANGED_COMMANDS =
        [
            "sadd",
            "zadd",
            "srem",
            "zrem",
            "zremrangebyrank",
            "zremrangebyscore",
            "zremrangebylex",
            "hsetnx",
            "hdel",
            "linsert",
            "lpushx",
            "rpushx",
            "lrem",
            "mapped_msetnx",
            "msetnx",
            "move",
            "persist",
            "renamenx",
            "sdiffstore",
            "setnx",
            "sinterstore",
            "smove",
            "sunionstore",
            "zinterstore",
            "zunionstore",
        ]
    NIL_FAIL_COMMANDS    =
        [
            "lpop",
            "rpop",
            "rpoplpush",
            "spop",
        ]
    POP_COMMANDS         =
        [
            "blpop",
            "brpop",
        ]
    WRITE_COMMANDS       =
        [
            "append",
            "bitop",
            "brpoplpush",
            "decr",
            "decrby",
            "del",
            "expire",
            "expireat",
            "getset",
            "hset",
            "hincrby",
            "hincrbyfloat",
            "hmset",
            "incr",
            "incrby",
            "incrbyfloat",
            "lpush",
            "lset",
            "ltrim",
            "mapped_hmset",
            "mapped_mset",
            "mset",
            "pexpire",
            "pexpireat",
            "psetex",
            "rename",
            "restore",
            "rpush",
            "set",
            "setbit",
            "setex",
            "setrange",
            "sort",
            "zincrby",
            "[]=",
        ]
    READ_COMMANDS        =
        [
            "bitcount",
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
            "zlexcount",
            "zrange",
            "zrangebylex",
            "zrangebyscore",
            "zrank",
            "zrevrange",
            "zrevrangebylex",
            "zrevrangebyscore",
            "zrevrank",
            "zscan",
            "zscan_each",
            "zscore",
            "[]",
        ]
    ALL_COMMANDS         =
        READ_COMMANDS +
            FLUSH_COMMANDS +
            NUM_CHANGED_COMMANDS +
            NIL_FAIL_COMMANDS +
            POP_COMMANDS +
            WRITE_COMMANDS

    OVERRIDE_COMMANDS =
        {
            "sdiffstore"  => [:first],
            "sinterstore" => [:first],
            "zinterstore" => [:first],
            "sunionstore" => [:first],
            "zunionstore" => [:first],
        }
    attr_accessor :options

    def initialize(start_method, end_method, table, options)
      @redis      = table
      @redis_name = nil

      clear_set :@initial_keys
      clear_set :@suite_altered_keys
      clear_set :@updated_keys
      clear_set :@read_keys
      clear_list_array :@multi_commands
      set_value_bool :@in_multi, false
      set_value_bool :@in_redis_cleanup, false
      set_value_bool :@suspend_tracking, false

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

    def method_missing(command, *args, &block)
      normalized_command = command.to_s.downcase

      if redis.respond_to?(normalized_command)
        if (normalized_command == "pipelined" ||
            (normalized_command == "multi" && block)) &&
            !get_value_bool(:@suspend_tracking)
          set_value_bool :@in_multi, true
          normalized_command = "exec"
        end

        initial_keys = nil
        if FLUSH_COMMANDS.include?(normalized_command)
          initial_keys = get_set(:@initial_keys)
        end

        response = redis.send(command, *args, &block)

        if FLUSH_COMMANDS.include?(normalized_command)
          add_set_values :@updated_keys, *initial_keys.to_a
        end

        if get_value_bool(:@in_multi) && !(["exec", "discard"].include?(normalized_command))
          append_list_value_array :@multi_commands, [normalized_command, *args]
        else
          process_command(response, normalized_command, *args)
        end

        response
      else
        super
      end
    end

    def process_command(response, *args)
      unless get_value_bool(:@in_redis_cleanup) || get_value_bool(:@suspend_tracking)
        if "multi" == args[0]
          set_value_bool :@in_multi, true
          clear_list_array :@multi_commands
        elsif ["exec", "pipelined"].include?(args[0])
          begin
            if (!response && get_list_length(:@multi_commands) > 0) ||
                (response && response.length != get_list_length(:@multi_commands))
              puts "exec response does not match sent commands.\n  response: #{response}\n  commands: #{get_list_array(:@multi_commands)}"

              # make the response length match the commands length.
              # so far the only time this has happened was when a multi returned nil which SHOULD indicate a failure
              #
              # I am assuming that the multi failed in this case, but even if so, it is safest for tracking purposes
              # to assume that redis DID change and record it as such.  Even if I am wrong, for the cleaner, it
              # doesn't matter, and there is no harm.
              response ||= []
              get_list_array(:@multi_commands).each_with_index do |command, index|
                if response.length < index
                  response << true
                end
              end
            end

            get_list_array(:@multi_commands).each_with_index do |command, index|
              process_command(response[index], *command)
            end
          ensure
            set_value_bool :@in_multi, false
            clear_list_array :@multi_commands
          end
        elsif "discard" == args[0]
          set_value_bool :@in_multi, false
          clear_list_array :@multi_commands
        elsif WRITE_COMMANDS.include?(args[0])
          add_set_values :@updated_keys, *extract_keys(*args)
        elsif NUM_CHANGED_COMMANDS.include?(args[0])
          update_key = true
          if [true, false].include?(response)
            update_key = response
          else
            update_key = response > 0 rescue true
          end

          if update_key
            add_set_values :@updated_keys, *extract_keys(*args)
          end
        elsif POP_COMMANDS.include?(args[0])
          if response
            add_set_value :@updated_keys, response[0]
          end
        elsif NIL_FAIL_COMMANDS.include?(args[0])
          if response
            add_set_values :@updated_keys, *extract_keys(*args)
          end
        elsif track_reads && READ_COMMANDS.include?(args[0])
          extract_keys(*args).each do |value|
            add_set_value :@read_keys, "\"#{value}\" - \"#{response}\""
          end
        end
      end
    end

    def respond_to_missing?(command, include_all=false)
      return true if ALL_COMMANDS.include?(command.to_s.downcase)

      # blind passthrough is deprecated and will be removed in 2.0
      if redis.respond_to?(command, include_all)
        return true
      end

      defined?(super) && super
    end

    def extract_key(arg)
      if arg.is_a?(Array)
        arg
      elsif arg.is_a?(Hash)
        arg.keys
      else
        [arg]
      end
    end

    def extract_keys(command, *args)
      handling     = OVERRIDE_COMMANDS[command.to_s.downcase] || PseudoCleaner::RedisCleaner::COMMANDS[command.to_s.downcase]
      message_keys = []

      (before, after) = handling

      case before
        when :first
          if args[0]
            extract_key(args[0]).each do |key|
              message_keys << key
            end
          end

        when :all
          args.each do |arg|
            extract_key(arg).each do |key|
              message_keys << key
            end
          end

        when :exclude_first
          args.each do |arg|
            extract_key(arg).each do |key|
              message_keys << key
            end
          end
          message_keys.shift

        when :exclude_last
          args.each do |arg|
            extract_key(arg).each do |key|
              message_keys << key
            end
          end
          message_keys.pop unless message_keys.length == 1

        when :exclude_options
          args.each do |arg|
            message_keys << arg unless arg.is_a?(Hash)
          end

        when :alternate
          args.each_with_index do |arg, i|
            if i.even?
              extract_key(arg).each do |key|
                message_keys << key
              end
            end
          end

        when :sort
          if args[-1].is_a?(Hash)
            if args[-1][:store] || args[-1]["store"]
              message_keys << (args[-1][:store] || args[-1]["store"])
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

        start_monitor
      end

      puts "  RedisCleaner(#{redis_name}) time: #{time}" if PseudoCleaner::Configuration.instance.benchmark
    end

    def suspend_tracking(&block)
      begin
        set_value_bool :@suspend_tracking, true

        block.yield
      ensure
        set_value_bool :@suspend_tracking, false
      end
    end

    def test_start test_strategy
      time = Benchmark.measure do
        puts "  RedisCleaner(#{redis_name})" if PseudoCleaner::Configuration.instance.benchmark

        synchronize_test_values do |test_values, read_values|
          if (test_values && !test_values.empty?) || (read_values && !read_values.empty?)
            report_dirty_values "values altered before the test started", test_values
            report_dirty_values "values read before the test started", read_values if track_reads

            test_values.each do |value|
              redis.del value unless set_includes?(:@initial_keys, value)
            end
          end
        end

        clear_set :@updated_keys
        clear_set :@read_keys
      end

      puts "  RedisCleaner(#{redis_name}) time: #{time}" if PseudoCleaner::Configuration.instance.benchmark
    end

    def test_end test_strategy
      time = Benchmark.measure do
        puts "  RedisCleaner(#{redis_name})" if PseudoCleaner::Configuration.instance.benchmark

        synchronize_test_values do |updated_values, read_values|
          if (updated_values && !updated_values.empty?) || (read_values && !read_values.empty?)
            report_keys = []

            if @options[:output_diagnostics]
              report_dirty_values "updated values", updated_values
              report_dirty_values "read values", read_values if track_reads
            end

            updated_values.each do |value|
              if set_includes?(:@initial_keys, value)
                report_keys << value
                add_set_value(:@suite_altered_keys, value) unless ignore_key(value)
              else
                redis.del(value)
              end
            end

            report_dirty_values "initial values altered by test", report_keys
          end
        end

        clear_set :@updated_keys
        clear_set :@read_keys
      end

      puts "  RedisCleaner(#{redis_name}) time: #{time}" if PseudoCleaner::Configuration.instance.benchmark
    end

    def suite_end test_strategy
      time = Benchmark.measure do
        puts "  RedisCleaner(#{redis_name})" if PseudoCleaner::Configuration.instance.benchmark

        new_keys = report_end_of_suite_state "suite end"

        new_keys.each do |key_value|
          redis.del key_value
        end
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

        synchronize_test_values do |updated_values, read_values|
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

        synchronize_test_values do |updated_values, read_values|
          if (updated_values && !updated_values.empty?) || (read_values && !read_values.empty?)
            output_values = false

            updated_values = updated_values.select { |value| !ignore_key(value) }
            read_values    = read_values.select { |value| !ignore_key(value) }
            if PseudoCleaner::MasterCleaner.report_table
              Cornucopia::Util::ReportTable.new(nested_table:         PseudoCleaner::MasterCleaner.report_table,
                                                nested_table_label:   redis_name,
                                                suppress_blank_table: true) do |report_table|
                updated_values.each_with_index do |updated_value, index|
                  updated_value, read_value = split_read_values(updated_value)
                  unless ignore_key(updated_value)
                    output_values = true
                    report_table.write_stats index.to_s, report_record(updated_value)
                    report_table.write_stats "", read_value if read_value
                  end
                end
              end

              if track_reads
                Cornucopia::Util::ReportTable.new(nested_table:         PseudoCleaner::MasterCleaner.report_table,
                                                  nested_table_label:   "#{redis_name} - reads",
                                                  suppress_blank_table: true) do |report_table|
                  read_values.each_with_index do |updated_value, index|
                    updated_value, read_value = split_read_values(updated_value)
                    unless ignore_key(updated_value)
                      output_values = true
                      report_table.write_stats index.to_s, report_record(updated_value)
                      report_table.write_stats "", read_value if read_value
                    end
                  end
                end
              end
            else
              PseudoCleaner::Logger.write("  #{redis_name}")

              updated_values.each_with_index do |updated_value, index|
                updated_value, read_value = split_read_values(updated_value)
                unless ignore_key(updated_value)
                  output_values = true
                  PseudoCleaner::Logger.write("    #{index}: #{report_record(updated_value)}")
                  PseudoCleaner::Logger.write("       #{read_value}") if read_value
                end
              end

              if track_reads
                PseudoCleaner::Logger.write("  #{redis_name} - reads")

                read_values.each_with_index do |updated_value, index|
                  updated_value, read_value = split_read_values(updated_value)
                  unless ignore_key(updated_value)
                    output_values = true
                    PseudoCleaner::Logger.write("    #{index}: #{report_record(updated_value)}")
                    PseudoCleaner::Logger.write("       #{read_value}") if read_value
                  end
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

      initial_key_set = get_set(:@initial_keys)

      deleted_keys = initial_key_set - current_keys
      new_keys     = current_keys - initial_key_set

      # filter out values we inserted that will go away on their own.
      new_keys     = new_keys.select { |key| (key =~ /redis_cleaner::synchronization_(?:end_)?key_[0-9]+_[0-9]+/).nil? }

      report_dirty_values "new values as of #{report_reason}", new_keys
      report_dirty_values "values deleted before #{report_reason}", deleted_keys
      report_dirty_values "initial values changed during suite run", get_set(:@suite_altered_keys)

      clear_set :@suite_altered_keys

      new_keys
    end

    def synchronize_test_values(&block)
      if get_value_bool(:@in_multi)
        # Ideally we should never get here, but if we do, assume everything was changed and keep moving...
        get_list_array(:@multi_commands).each do |args|
          if WRITE_COMMANDS.include?(args[0]) ||
              POP_COMMANDS.include?(args[0]) ||
              NIL_FAIL_COMMANDS.include?(args[0]) ||
              NUM_CHANGED_COMMANDS.include?(args[0])
            add_set_values :@updated_keys, *extract_keys(*args)
          elsif track_reads && READ_COMMANDS.include?(args[0])
            add_set_values :@read_keys, *extract_keys(*args)
          end
        end

        set_value_bool(:@in_multi, false)
        clear_list_array(:@multi_commands)
      end

      updated_values = get_set(:@updated_keys).dup
      read_values    = get_set(:@read_keys).dup

      set_value_bool :@in_redis_cleanup, true

      begin
        block.yield updated_values, read_values
      ensure
        set_value_bool :@in_redis_cleanup, false
      end
    end

    def start_monitor
      redis_keys = redis.keys
      clear_set :@initial_keys, redis_keys
      clear_set :@suite_altered_keys
      clear_set :@updated_keys
      clear_set :@read_keys
      clear_list_array :@multi_commands
      set_value_bool :@in_multi, false
      set_value_bool :@in_redis_cleanup, false
      set_value_bool :@suspend_tracking, false

      if @options[:output_diagnostics]
        if PseudoCleaner::MasterCleaner.report_table
          Cornucopia::Util::ReportTable.new(nested_table:         PseudoCleaner::MasterCleaner.report_table,
                                            nested_table_label:   redis_name,
                                            suppress_blank_table: true) do |report_table|
            report_table.write_stats "initial keys count", redis_keys.count
          end
        else
          PseudoCleaner::Logger.write("#{redis_name}")
          PseudoCleaner::Logger.write("    Initial keys count - #{redis_keys.count}")
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
          key_hash[:set] = { len: redis.scard(key_name), values: redis.smembers(key_name) }
        when "zset"
          sorted_set_values = redis.zrange(key_name, 0, -1).reduce({}) do |hash, set_value|
            hash[set_value] = redis.zscore(key_name, set_value)
            hash
          end

          key_hash[:sorted_set] = { len: redis.zcard(key_name), values: sorted_set_values }
        when "hash"
          key_hash[:hash] = { len: redis.hlen(key_name), values: redis.hgetall(key_name) }
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

    def split_read_values(key)
      if key =~ /\".*\" - \".*\"/
        vals = key.split("\" - \"")
        [vals[0][1..-1], vals[1..-1].join("\" - \"")[0..-2]]
      else
        [key, nil]
      end
    end

    def report_dirty_values message, test_values
      test_values = test_values.select { |value| !ignore_key(split_read_values(value)[0]) }

      if test_values && !test_values.empty?
        output_values = false

        if PseudoCleaner::MasterCleaner.report_table
          Cornucopia::Util::ReportTable.new(nested_table:         PseudoCleaner::MasterCleaner.report_table,
                                            nested_table_label:   redis_name,
                                            suppress_blank_table: true) do |report_table|
            report_table.write_stats "action", message
            test_values.each_with_index do |key_name, index|
              key_name, read_value = split_read_values(key_name)
              unless ignore_key(key_name)
                output_values = true
                report_table.write_stats index, report_record(key_name)
                report_table.write_stats("", read_value) if read_value
              end
            end
          end
        else
          test_values.each do |key_name|
            key_name, read_value = split_read_values(key_name)
            unless ignore_key(key_name)
              PseudoCleaner::Logger.write("********* RedisCleaner - #{message}".red.on_light_white) unless output_values
              output_values = true
              PseudoCleaner::Logger.write("  #{key_name}: #{report_record(key_name)}".red.on_light_white)
              PseudoCleaner::Logger.write("     #{read_value}".red.on_light_white) if read_value
            end
          end
        end

        PseudoCleaner::MasterCleaner.report_error if output_values
      end
    end

    def set_value_bool(value_name, bool_value)
      instance_variable_set(value_name, bool_value)
    end

    def get_value_bool(value_name)
      instance_variable_get(value_name)
    end

    def append_list_value_array(value_name, array_value)
      array = instance_variable_get(value_name)
      array << array_value
    end

    def get_list_length(value_name)
      instance_variable_get(value_name).length
    end

    def get_list_array(value_name)
      instance_variable_get(value_name)
    end

    def clear_list_array(value_name)
      instance_variable_set(value_name, [])
    end

    def clear_set(value_name, keys = nil)
      if keys
        instance_variable_set(value_name, SortedSet.new(keys))
      else
        instance_variable_set(value_name, SortedSet.new)
      end
    end

    def add_set_values(value_name, *values)
      set = get_set(value_name)

      set.merge(values)
    end

    def add_set_value(value_name, value)
      set = get_set(value_name)

      set << value
    end

    def remove_set_value(value_name, value)
      set = get_set(value_name)

      set.delete value
    end

    def set_includes?(value_name, value)
      set = get_set(value_name)

      set.include?(value)
    end

    def get_set(value_name)
      set = instance_variable_get(value_name)

      unless set
        set = SortedSet.new
        instance_variable_set(value_name, set)
      end

      set
    end

    def track_reads=(value)
      @track_reads = value
    end

    def track_reads
      @track_reads ||= PseudoCleaner::Configuration.instance.redis_track_reads
    end
  end
end