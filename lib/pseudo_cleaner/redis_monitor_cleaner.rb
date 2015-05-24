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
  class RedisMonitorCleaner
    # SUITE_KEY = "PseudoDelete::RedisMonitorCleaner:initial_redis_state"

    FLUSH_COMMANDS =
        [
            "flushall",
            "flushdb"
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
            "sadd",
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
            "srem",
            "sunionstore",
            "zadd",
            "zincrby",
            "zinterstore",
            "zrem",
            "zremrangebyrank",
            "zremrangebyscore",
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
        ]

    attr_reader :monitor_thread
    attr_reader :initial_keys
    attr_accessor :options

    class RedisMessage
      attr_reader :message
      attr_reader :time_stamp
      attr_reader :db
      attr_reader :host
      attr_reader :port
      attr_reader :command
      attr_reader :cur_pos

      def initialize(message_string)
        @message = message_string

        parse_message
      end

      def parse_message
        if @message =~ /[0-9]+\.[0-9]+ \[[0-9]+ [^:]+:[^\]]+\] \"[^\"]+\"/
          end_pos     = @message.index(" ")
          @time_stamp = @message[0..end_pos - 1]

          @cur_pos = end_pos + 2 # " ["
          end_pos  = @message.index(" ", @cur_pos)
          @db      = @message[@cur_pos..end_pos - 1].to_i

          @cur_pos = end_pos + 1
          end_pos  = @message.index(":", @cur_pos)
          @host    = @message[@cur_pos..end_pos - 1]

          @cur_pos = end_pos + 1
          end_pos  = @message.index("]", @cur_pos)
          @port    = @message[@cur_pos..end_pos - 1].to_i

          @cur_pos = end_pos + 2 # "] "
          @command = next_value.downcase
        else
          @command = @message
        end
      end

      def next_value
        in_quote = (@message[@cur_pos] == '"')
        if in_quote
          @cur_pos += 1
          end_pos  = @cur_pos
          while (end_pos && end_pos < @message.length)
            end_pos = @message.index("\"", end_pos)

            num_backslashes = 0
            back_pos        = end_pos

            while @message[back_pos - 1] == "\\"
              num_backslashes += 1
              back_pos        -= 1
            end

            break if (num_backslashes % 2) == 0
            end_pos += 1
          end
        else
          end_pos = @message.index(" ", @cur_pos)
        end
        the_value = @message[@cur_pos..end_pos - 1]
        end_pos   += 1 if in_quote

        @cur_pos = end_pos + 1

        the_value.gsub("\\\\", "\\").gsub("\\\"", "\"")
      end

      def keys
        unless defined?(@message_keys)
          @message_keys = []

          if Redis::Namespace::COMMANDS.include? command
            handling = Redis::Namespace::COMMANDS[command.to_s.downcase]

            (before, after) = handling

            case before
              when :first
                @message_keys << next_value

              when :all
                while @cur_pos < @message.length
                  @message_keys << next_value
                end

              when :exclude_first
                next_value
                while @cur_pos < @message.length
                  @message_keys << next_value
                end

              when :exclude_last
                while @cur_pos < @message.length
                  @message_keys << next_value
                end
                @message_keys.delete_at(@message_keys.length - 1)

              when :exclude_options
                options = ["weights", "aggregate", "sum", "min", "max"]
                while @cur_pos < @message.length
                  @message_keys << next_value
                  if options.include?(@message_keys[-1].downcase)
                    @message_keys.delete_at(@message_keys.length - 1)
                    break
                  end
                end

              when :alternate
                while @cur_pos < @message.length
                  @message_keys << next_value
                  next_value
                end

              when :sort
                next_value

                while @cur_pos < @message.length
                  a_value = next_value
                  if a_value.downcase == "store"
                    @message_keys[0] = next_value
                  end
                end

              # when :eval_style
              #
              # when :scan_style
            end
          end
        end

        @message_keys
      end

      def to_s
        {
            time_stamp: time_stamp,
            db:         db,
            host:       host,
            port:       port,
            command:    command,
            message:    message,
            cur_pos:    cur_pos
        }.to_s
      end
    end

    def initialize(start_method, end_method, table, options)
      @initial_keys       = SortedSet.new
      @monitor_thread     = nil
      @redis_name         = nil
      @suite_altered_keys = SortedSet.new

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

    def <=>(right_object)
      if (right_object.is_a?(PseudoCleaner::RedisMonitorCleaner))
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
      @test_strategy ||= test_strategy

      # if redis.type(PseudoCleaner::RedisMonitorCleaner::SUITE_KEY) == "set"
      #   @initial_keys = SortedSet.new(redis.smembers(PseudoCleaner::RedisMonitorCleaner::SUITE_KEY))
      #   report_end_of_suite_state "before suite start"
      # end
      # redis.del PseudoCleaner::RedisMonitorCleaner::SUITE_KEY

      start_monitor
    end

    def test_start test_strategy
      @test_strategy ||= test_strategy

      synchronize_test_values do |test_values|
        if test_values && !test_values.empty?
          report_dirty_values "values altered before the test started", test_values

          test_values.each do |value|
            redis.del value unless initial_keys.include?(value)
          end
        end
      end
    end

    def test_end test_strategy
      synchronize_test_values do |updated_values|
        if updated_values && !updated_values.empty?
          report_keys = []

          if @options[:output_diagnostics]
            report_dirty_values "updated values", updated_values
          end

          updated_values.each do |value|
            if initial_keys.include?(value)
              report_keys << value
              @suite_altered_keys << value
            else
              redis.del(value)
            end
          end

          report_dirty_values "initial values altered by test", report_keys
        end
      end
    end

    def suite_end test_strategy
      report_end_of_suite_state "suite end"

      if monitor_thread
        monitor_thread.kill
        @monitor_thread = nil
      end
    end

    def reset_suite
      report_end_of_suite_state "reset suite"

      if monitor_thread
        monitor_thread.kill
        @monitor_thread = nil
        start_monitor
      end
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

    def peek_values
      synchronize_test_values do |updated_values|
        if updated_values && !updated_values.empty?
          output_values = false

          if PseudoCleaner::MasterCleaner.report_table
            Cornucopia::Util::ReportTable.new(nested_table:         PseudoCleaner::MasterCleaner.report_table,
                                              nested_table_label:   redis_name,
                                              suppress_blank_table: true) do |report_table|
              updated_values.each do |updated_value|
                unless ignore_key(updated_value)
                  output_values = true
                  report_table.write_stats updated_value, report_record(updated_value)
                end
              end
            end
          else
            PseudoCleaner::Logger.write("  #{redis_name}")

            updated_values.each do |updated_value|
              unless ignore_key(updated_value)
                output_values = true
                PseudoCleaner::Logger.write("    #{updated_value}: #{report_record(updated_value)}")
              end
            end
          end

          PseudoCleaner::MasterCleaner.report_error if output_values
        end
      end
    end

    def synchronize_key
      @synchronize_key ||= "redis_cleaner::synchronization_key_#{rand(1..1_000_000_000_000_000_000)}_#{rand(1..1_000_000_000_000_000_000)}"
    end

    def synchronize_end_key
      @synchronize_end_key ||= "redis_cleaner::synchronization_end_key_#{rand(1..1_000_000_000_000_000_000)}_#{rand(1..1_000_000_000_000_000_000)}"
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
      updated_values = nil

      if monitor_thread
        redis.setex(synchronize_key, 1, true)
        updated_values = queue.pop
      end

      block.yield updated_values

      redis.setex(synchronize_end_key, 1, true)
    end

    def queue
      @queue ||= Queue.new
    end

    def start_monitor
      cleaner_class = self

      @initial_keys = SortedSet.new(redis.keys)
      # @initial_keys.add(PseudoCleaner::RedisMonitorCleaner::SUITE_KEY)
      # @initial_keys.each do |key_value|
      #   redis.sadd(PseudoCleaner::RedisMonitorCleaner::SUITE_KEY, key_value)
      # end
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

      unless @monitor_thread
        @monitor_thread = Thread.new do
          in_redis_cleanup = false
          updated_keys     = SortedSet.new

          monitor_redis    = Redis.new(cleaner_class.redis.client.options)
          redis_options    = monitor_redis.client.options.with_indifferent_access
          cleaner_class_db = redis_options[:db]

          monitor_redis.monitor do |message|
            redis_message = RedisMessage.new message

            if redis_message.db == cleaner_class_db
              process_command = true

              if redis_message.command == "setex"
                if redis_message.keys[0] == cleaner_class.synchronize_key
                  process_command = false

                  in_redis_cleanup = true
                  return_values    = updated_keys
                  updated_keys     = SortedSet.new
                  cleaner_class.queue << return_values
                elsif redis_message.keys[0] == cleaner_class.synchronize_end_key
                  in_redis_cleanup                       = false
                  cleaner_class.monitor_thread[:updated] = nil
                  process_command                        = false
                end
              elsif redis_message.command == "del"
                if in_redis_cleanup
                  process_command = false
                end
              end

              if process_command
                # flush...
                if PseudoCleaner::RedisMonitorCleaner::WRITE_COMMANDS.include? redis_message.command
                  updated_keys.merge(redis_message.keys)
                elsif PseudoCleaner::RedisMonitorCleaner::FLUSH_COMMANDS.include? redis_message.command
                  # Not sure I can get the keys at this point...
                  # updated_keys.merge(cleaner_class.redis.keys)
                end
              end
            elsif "flushall" == redis_message.command
              # Not sure I can get the keys at this point...
              # updated_keys.merge(cleaner_class.redis.keys)
            end
          end
        end

        sleep(0.01)
        redis.get(synchronize_key)
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
          PseudoCleaner::Logger.write("********* RedisMonitorCleaner - #{message}".red.on_light_white)
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