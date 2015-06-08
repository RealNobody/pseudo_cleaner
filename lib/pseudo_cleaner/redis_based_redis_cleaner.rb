require "pseudo_cleaner/redis_cleaner"
require "json"

module PseudoCleaner
  class RedisBasedRedisCleaner < PseudoCleaner::RedisCleaner
    def base_key
      "PseudoCleaner::RedisBasedRedisCleaner"
    end

    def settings_redis
      @settings_redis ||= Redis.new(redis.client.options)
    end

    def ignore_key(key)
      key =~ /#{base_key}/ ||
          ignore_regexes.detect { |ignore_regex| key =~ ignore_regex }
    end

    def bool_name(value_name)
      "#{base_key}::#{value_name}"
    end

    def set_value_bool(value_name, bool_value)
      settings_redis.set bool_name(value_name), (!!bool_value).to_s
    end

    def get_value_bool(value_name)
      settings_redis.get(bool_name(value_name)) != "false"
    end

    def list_name(value_name)
      "#{base_key}::#{value_name}"
    end

    def sub_list_name(value_name, index)
      "#{list_name(value_name)}::#{index}"
    end

    def append_list_value_array(value_name, array_value)
      list_len = settings_redis.llen list_name(value_name)

      sub_name = sub_list_name(value_name, list_len)

      settings_redis.multi do
        array_value.each do |value|
          if value.is_a?(Hash)
            settings_redis.rpush sub_name, "h#{value.to_json}"
          else
            settings_redis.rpush sub_name, "s#{value}"
          end
        end

        settings_redis.rpush list_name(value_name), sub_name
      end
    end

    def get_list_length(value_name)
      settings_redis.llen list_name(value_name)
    end

    def get_list_array(value_name)
      list_len = settings_redis.llen list_name(value_name)

      list_array = []
      list_len.times do |index|
        sub_name = sub_list_name value_name, index

        value_array = []
        values      = settings_redis.lrange(sub_name, 0, -1)

        values.each do |value|
          if value [0] == "h"
            value = JSON.parse(value[1..-1])
          else
            value = value[1..-1]
          end

          value_array << value
        end

        list_array << value_array
      end

      list_array
    end

    def clear_list_array(value_name)
      settings_redis.lrange(list_name(value_name), 0, -1).each do |sub_list_name|
        settings_redis.del sub_list_name
      end

      settings_redis.del list_name(value_name)
    end

    def set_name(value_name)
      "#{base_key}::#{value_name}"
    end

    def clear_set(value_name, keys = nil)
      clear_name = set_name(value_name)
      settings_redis.del clear_name

      if keys
        keys.each do |key|
          settings_redis.sadd clear_name, key
        end
      end
    end

    def add_set_values(value_name, *values)
      add_name = set_name(value_name)

      settings_redis.multi do
        values.each do |value|
          settings_redis.sadd add_name, value
        end
      end
    end

    def add_set_value(value_name, value)
      settings_redis.sadd set_name(value_name), value
    end

    def remove_set_value(value_name, value)
      settings_redis.srem set_name(value_name), value
    end

    def set_includes?(value_name, value)
      settings_redis.sismember set_name(value_name), value
    end

    def get_set(value_name)
      SortedSet.new(settings_redis.smembers(set_name(value_name)))
    end

    def suite_end test_strategy
      super test_strategy

      settings_redis.keys("#{base_key}*").each do |key|
        settings_redis.del key
      end
    end
  end
end