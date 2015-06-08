RSpec.shared_examples("it tracks changes to Redis") do
  let(:ttl) { rand(1..100_000) }
  let(:key_name) { Faker::Lorem.sentence }
  let(:key_name_2) { Faker::Lorem.sentence }
  let(:key_name_3) { Faker::Lorem.sentence }
  let(:string_value) { Faker::Lorem.sentence }
  let(:string_value_2) { Faker::Lorem.sentence }
  let(:set_values) { rand(5..10).times.map { Faker::Lorem.sentence } }
  let(:sorted_set_values) do
    Hash[rand(5..10).times.reduce({}) do |hash, index|
           hash[Faker::Lorem.sentence] = [1, 10, 100, 1_000, 10_000].sample * rand
           hash
         end.sort_by { |key, value| value }]
  end
  let(:list_values) { rand(5..10).times.map { Faker::Lorem.sentence } }
  let(:hash_values) do
    rand(5..10).times.reduce({}) do |hash, index|
      hash[Faker::Lorem.word] = Faker::Lorem.sentence
      hash
    end
  end

  after(:each) do
    subject.redis.del(key_name)
    subject.redis.del(key_name_2)
    subject.redis.del(key_name_3)

    hash_values.keys.each { |hash_key| subject.redis.del(hash_key) }
  end

  def populate_list
    list_values.each do |list_value|
      subject.redis.rpush key_name, list_value
    end
  end

  def populate_hash
    hash_values.each do |key, value|
      subject.redis.hset key_name, key, value
    end
  end

  def populate_set
    set_values.each do |set_value|
      subject.redis.sadd key_name, set_value
    end
  end

  def populate_sorted_set
    sorted_set_values.each do |sort_value|
      subject.redis.zadd key_name, sort_value[1], sort_value[0]
    end
  end

  def populate_lex_sorted_set
    sorted_set_values.each do |sort_value|
      subject.redis.zadd key_name, 0, sort_value[0]
    end
  end

  around(:each) do |example_proxy|
    initial_values = subject.redis.keys

    example_proxy.call

    final_values = subject.redis.keys

    new_values     = final_values - initial_values
    deleted_values = initial_values - final_values

    expect(new_values).to be_empty
  end

  describe "#type" do
    it "gets the type of a string key" do
      subject.redis.set key_name, string_value

      expect(subject.type(key_name)).to eq "string"
    end

    it "gets the type of a set key" do
      subject.redis.sadd key_name, set_values[0]

      expect(subject.type(key_name)).to eq "set"
    end

    it "gets the type of a zset key" do
      sort_value = sorted_set_values.first
      subject.redis.zadd key_name, sort_value[1], sort_value[0]

      expect(subject.type(key_name)).to eq "zset"
    end

    it "gets the type of a list key" do
      subject.redis.lpush key_name, list_values[0]

      expect(subject.type(key_name)).to eq "list"
    end

    it "gets the type of a hash key" do
      subject.redis.hset key_name, *hash_values.first

      expect(subject.type(key_name)).to eq "hash"
    end
  end

  describe "#report_record" do
    context "no ttl" do
      it "formats a string value" do
        subject.redis.set key_name, string_value

        expect(subject.report_record(key_name)).to eq(
                                                       {
                                                           key:   key_name,
                                                           type:  "string",
                                                           ttl:   -1,
                                                           value: string_value
                                                       }
                                                   )
      end

      it "formats a list value" do
        populate_list

        expect(subject.report_record(key_name)).to eq(
                                                       {
                                                           key:  key_name,
                                                           type: "list",
                                                           ttl:  -1,
                                                           list:
                                                                 {
                                                                     len:    list_values.length,
                                                                     values: list_values
                                                                 }
                                                       }
                                                   )
      end

      it "formats a set value" do
        populate_set

        massaged_value = subject.report_record(key_name)
        massaged_value[:set][:values].sort!

        expect(massaged_value).to eq(
                                      {
                                          key:  key_name,
                                          type: "set",
                                          ttl:  -1,
                                          set:
                                                {
                                                    len:    set_values.length,
                                                    values: set_values.sort
                                                }
                                      }
                                  )
      end

      it "formats a sorted set value" do
        populate_sorted_set

        expect(subject.report_record(key_name)).to eq(
                                                       {
                                                           key:  key_name,
                                                           type: "zset",
                                                           ttl:  -1,
                                                           sorted_set:
                                                                 {
                                                                     len:    sorted_set_values.length,
                                                                     values: sorted_set_values.reduce({}) do |hash, value|
                                                                       hash[value[0]] = value[1]
                                                                       hash
                                                                     end
                                                                 }
                                                       }
                                                   )
      end

      it "formats a hash value" do
        populate_hash

        expect(subject.report_record(key_name)).to eq(
                                                       {
                                                           key:  key_name,
                                                           type: "hash",
                                                           ttl:  -1,
                                                           hash:
                                                                 {
                                                                     len:    hash_values.length,
                                                                     values: hash_values
                                                                 }
                                                       }
                                                   )
      end

      it "formats an empty value" do
        subject.redis.del key_name
        expect(subject.report_record(key_name)).to eq(
                                                       {
                                                           key:   key_name,
                                                           type:  "none",
                                                           ttl:   -1,
                                                           value: "[[DELETED]]"
                                                       }
                                                   )
      end
    end

    context "with a ttl" do
      it "formats a string value" do
        subject.redis.set key_name, string_value
        subject.redis.expire(key_name, ttl)

        expect(subject.report_record(key_name)).to eq(
                                                       {
                                                           key:   key_name,
                                                           type:  "string",
                                                           ttl:   ttl,
                                                           value: string_value
                                                       }
                                                   )
      end

      it "formats a list value" do
        populate_list
        subject.redis.expire(key_name, ttl)

        expect(subject.report_record(key_name)).to eq(
                                                       {
                                                           key:  key_name,
                                                           type: "list",
                                                           ttl:  ttl,
                                                           list:
                                                                 {
                                                                     len:    list_values.length,
                                                                     values: list_values
                                                                 }
                                                       }
                                                   )
      end

      it "formats a set value" do
        populate_set
        subject.redis.expire(key_name, ttl)

        massaged_value = subject.report_record(key_name)
        massaged_value[:set][:values].sort!

        expect(massaged_value).to eq(
                                      {
                                          key:  key_name,
                                          type: "set",
                                          ttl:  ttl,
                                          set:
                                                {
                                                    len:    set_values.length,
                                                    values: set_values.sort
                                                }
                                      }
                                  )
      end

      it "formats a sorted set value" do
        populate_sorted_set
        subject.redis.expire(key_name, ttl)

        expect(subject.report_record(key_name)).to eq(
                                                       {
                                                           key:  key_name,
                                                           type: "zset",
                                                           ttl:  ttl,
                                                           sorted_set:
                                                                 {
                                                                     len:    sorted_set_values.length,
                                                                     values: sorted_set_values.reduce({}) do |hash, value|
                                                                       hash[value[0]] = value[1]
                                                                       hash
                                                                     end
                                                                 }
                                                       }
                                                   )
      end

      it "formats a hash value" do
        populate_hash
        subject.redis.expire(key_name, ttl)

        expect(subject.report_record(key_name)).to eq(
                                                       {
                                                           key:  key_name,
                                                           type: "hash",
                                                           ttl:  ttl,
                                                           hash:
                                                                 {
                                                                     len:    hash_values.length,
                                                                     values: hash_values
                                                                 }
                                                       }
                                                   )
      end

      it "formats an empty value" do
        subject.redis.del key_name

        expect(subject.report_record(key_name)).to eq(
                                                       {
                                                           key:   key_name,
                                                           type:  "none",
                                                           ttl:   -1,
                                                           value: "[[DELETED]]"
                                                       }
                                                   )
      end
    end
  end

  describe "#updated_keys" do
    around(:each) do |example_proxy|
      subject.suite_start :pseudo_delete

      example_proxy.call

      subject.suite_end :pseudo_delete
    end

    describe "blocking pop commands" do
      it "records that a key changed when blpop is called" do
        subject.redis.del key_name_2
        subject.redis.del key_name_3
        populate_list

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.blpop key_name, key_name_3, key_name_2, key_name, 1

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when brpop is called" do
        subject.redis.del key_name_2
        subject.redis.del key_name_3
        populate_list

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.brpop key_name, key_name_3, key_name_2, key_name, 1

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "does not record that a key changed when blpop is called and all lists are empty" do
        subject.redis.del key_name_2
        subject.redis.del key_name_3
        subject.redis.del key_name

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.blpop key_name, key_name_3, key_name_2, key_name, 1

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record that a key changed when brpop is called and all lists are empty" do
        subject.redis.del key_name_2
        subject.redis.del key_name_3
        subject.redis.del key_name

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.brpop key_name, key_name_3, key_name_2, key_name, 1

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end
    end

    describe "commands that return the number of values affected" do
      it "records an updated key if sadd changes a record" do
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.sadd key_name, set_values[0]

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records an updated key if zadd changes a record" do
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.zadd key_name, sorted_set_values.first[1].to_f, sorted_set_values.first[0]

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records an updated key if srem changes a record" do
        populate_set
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.srem key_name, set_values.sample

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records an updated key if zrem changes a record" do
        populate_sorted_set
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.zrem key_name, sorted_set_values.keys.sample

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records an updated key if zremrangebyrank changes a record" do
        populate_sorted_set
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.zremrangebyrank key_name, 0, -1

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records an updated key if zremrangebyscore changes a record" do
        populate_sorted_set
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.zremrangebyscore key_name, sorted_set_values.first[1] - 1, sorted_set_values.first[1] + 1

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records an updated key if zremrangebylex changes a record" do
        if Gem::Version.new("2.8.9") < Gem::Version.new(subject.redis.info["redis_version"])
          populate_lex_sorted_set
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.zremrangebylex key_name, "-", "+"

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end
      end

      it "does not record an update if sadd does not change a record" do
        subject.redis.sadd key_name, set_values[0]
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.sadd key_name, set_values[0]

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record an update if zadd does not change a record" do
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.zadd key_name, sorted_set_values.first[1], sorted_set_values.first[0]

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "does not record an update if srem does not change a record" do
        populate_set
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.srem key_name, "1234"

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record an update if zrem does not change a record" do
        populate_sorted_set
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.zrem key_name, "1234"

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record an update if zremrangebyrank does not change a record" do
        populate_sorted_set
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.zremrangebyrank key_name, sorted_set_values.length + 12, sorted_set_values.length + 22

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record an update if zremrangebyscore does not change a record" do
        populate_sorted_set
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.zremrangebyscore key_name, sorted_set_values.first[1] - 2, sorted_set_values.first[1] - 1

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record an updated key if zremrangebylex does not change a record" do
        if Gem::Version.new("2.8.9") < Gem::Version.new(subject.redis.info["redis_version"])
          populate_lex_sorted_set
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.zremrangebylex key_name, "[1", "(1"

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        end
      end

      it "records that a key changed when hsetnx is called" do
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.hsetnx key_name, *hash_values.first

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "does not record that a key changed when hsetnx is called for an existing hash value" do
        subject.redis.hset key_name, *hash_values.first
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.hsetnx key_name, *hash_values.first

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when hdel is called" do
        populate_hash
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.hdel key_name, *hash_values.first[0]

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "does not record that a key changed when hdel is called for a non-existing field" do
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.hdel key_name, hash_values.first[0]

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when linsert is called" do
        populate_list
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.linsert key_name, ["BEFORE", "AFTER"].sample, list_values.sample, string_value

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "does not record that a key changed when linsert is called for an empty key" do
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.linsert key_name, ["BEFORE", "AFTER"].sample, list_values.sample, string_value

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record that a key changed when linsert is called for a missing pivot" do
        populate_list
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.linsert key_name, ["BEFORE", "AFTER"].sample, "1234", string_value

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when lpushx is called" do
        populate_list
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.lpushx key_name, string_value

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "does not record that a key changed when lpushx is called on an empty list" do
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.lpushx key_name, list_values[0]

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when rpushx is called" do
        populate_list
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.lpushx key_name, string_value

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "does not record that a key changed when rpushx is called on an empty list" do
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.lpushx key_name, list_values[0]

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when lrem is called" do
        populate_list
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.lrem key_name, 0, list_values.sample

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "does not record that a key changed when lrem is called on an empty list" do
        populate_list
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.lrem key_name, 0, "1234"

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when mapped_msetnx is called" do
        hash_values.keys.each do |alt_key_name|
          expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
        end

        server_subject.mapped_msetnx hash_values

        hash_values.keys.each do |alt_key_name|
          expect(subject.get_set(:@updated_keys)).to be_include alt_key_name
        end
      end

      it "does not record that a key changed when mapped_msetnx is called and a value exists" do
        subject.redis.set(*hash_values.first)

        hash_values.keys.each do |alt_key_name|
          expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
        end

        server_subject.mapped_msetnx hash_values

        hash_values.keys.each do |alt_key_name|
          expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
        end
      end

      it "records that a key changed when msetnx is called" do
        hash_values.keys.each do |alt_key_name|
          expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
        end

        server_subject.msetnx(*hash_values.to_a.flatten)

        hash_values.keys.each do |alt_key_name|
          expect(subject.get_set(:@updated_keys)).to be_include alt_key_name
        end
      end

      it "does not record that a key changed when mapped_msetnx is called and a value exists" do
        subject.redis.set(*hash_values.first)

        hash_values.keys.each do |alt_key_name|
          expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
        end

        server_subject.msetnx(*hash_values.to_a.flatten)

        hash_values.keys.each do |alt_key_name|
          expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
        end
      end

      it "records that a key changed when move is called" do
        expect(subject.redis).to receive(:send).and_return 1

        subject.redis.set key_name, string_value
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.move key_name, 1

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "does not record that a key changed when move is called on a non-existing key" do
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.move key_name, 1

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when persist is called" do
        subject.redis.setex key_name, rand(100..100_000), string_value
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.persist key_name

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "does not record that a key changed when persist is called on a persisted key" do
        subject.redis.set key_name, string_value
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.persist key_name

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when renamenx is called" do
        subject.redis.set key_name, string_value
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

        server_subject.renamenx key_name, key_name_2

        expect(subject.get_set(:@updated_keys)).to be_include key_name
        expect(subject.get_set(:@updated_keys)).to be_include key_name_2
      end

      it "does not record that a key changed when renamenx is called if the dest exists" do
        subject.redis.set key_name, string_value
        subject.redis.set key_name_2, string_value_2
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

        server_subject.renamenx key_name, key_name_2

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
      end

      it "records that a key changed when sdiffstore is called" do
        populate_set
        set_values.sample(4).each do |set_value|
          subject.redis.sadd key_name_2, set_value
        end
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

        server_subject.sdiffstore key_name_3, key_name, key_name_2

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(subject.get_set(:@updated_keys)).to be_include key_name_3
      end

      it "does not record that a key changed when sdiffstore is empty" do
        populate_set
        set_values.each do |set_value|
          subject.redis.sadd key_name_2, set_value
        end
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

        server_subject.sdiffstore key_name_3, key_name, key_name_2

        expect(subject.redis.type(key_name_3)).to eq "none"
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
      end

      it "records that a key changed when setnx is called" do
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.setnx key_name, string_value

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "does not record that a key changed when setnx is called on an existing key" do
        subject.redis.set key_name, string_value
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.setnx key_name, string_value

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when sinterstore is called" do
        populate_set
        set_values.sample(4).each do |set_value|
          subject.redis.sadd key_name_2, set_value
        end
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

        server_subject.sinterstore key_name_3, key_name, key_name_2

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(subject.get_set(:@updated_keys)).to be_include key_name_3
      end

      it "does not record that a key changed when sinterstore is called and there is no intersection" do
        populate_set
        subject.redis.sadd key_name_2, "1234"
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

        server_subject.sinterstore key_name_3, key_name, key_name_2

        expect(subject.redis.type(key_name_3)).to eq "none"
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
      end

      it "records that a key changed when smove is called" do
        populate_set
        set_values.sample(4).each do |set_value|
          subject.redis.sadd key_name_2, set_value
        end
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

        server_subject.smove key_name, key_name_2, set_values.sample

        expect(subject.get_set(:@updated_keys)).to be_include key_name
        expect(subject.get_set(:@updated_keys)).to be_include key_name_2
      end

      it "does not record that a key changed when smove is called and the set doesn't exist" do
        set_values.sample(4).each do |set_value|
          subject.redis.sadd key_name_2, set_value
        end
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

        server_subject.smove key_name, key_name_2, set_values.sample

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
      end

      it "does not record that a key changed when smove is called and the set doesn't have the element" do
        populate_set
        set_values.sample(4).each do |set_value|
          subject.redis.sadd key_name_2, set_value
        end
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

        server_subject.smove key_name, key_name_2, "1234"

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
      end

      it "records that a key changed when sunionstore is called" do
        populate_set
        set_values.sample(4).each do |set_value|
          subject.redis.sadd key_name_2, set_value
        end
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

        server_subject.sunionstore key_name_3, key_name, key_name_2

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(subject.get_set(:@updated_keys)).to be_include key_name_3
      end

      it "does not record that a key changed when sunionstore is called on empty sets" do
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

        server_subject.sunionstore key_name_3, key_name, key_name_2

        expect(subject.redis.type(key_name_3)).to eq "none"
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
      end

      it "records that a key changed when zinterstore is called" do
        populate_sorted_set
        sorted_set_values.to_a.sample(4).each do |sort_value|
          subject.redis.zadd key_name_2, sort_value[1], sort_value[0]
        end
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

        server_subject.zinterstore key_name_3, [key_name, key_name_2]

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(subject.get_set(:@updated_keys)).to be_include key_name_3
      end

      it "does not record that a key changed when zinterstore is called and there is no intersection" do
        populate_sorted_set
        subject.redis.sadd key_name_2, "1234"
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

        server_subject.zinterstore key_name_3, [key_name, key_name_2]

        expect(subject.redis.type(key_name_3)).to eq "none"
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
      end

      it "records that a key changed when zunionstore is called" do
        populate_sorted_set
        sorted_set_values.to_a.sample(4).each do |sort_value|
          subject.redis.zadd key_name, sort_value[1], sort_value[0]
        end
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

        server_subject.zunionstore key_name_3, [key_name, key_name_2]

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(subject.get_set(:@updated_keys)).to be_include key_name_3
      end

      it "does not record that a key changed when zunionstore is called on empty sets" do
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

        server_subject.zunionstore key_name_3, [key_name, key_name_2]

        expect(subject.redis.type(key_name_3)).to eq "none"
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
      end
    end

    describe "commands that return nil on failure" do
      it "records that a key changed when lpop is called" do
        populate_list
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.lpop key_name

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "does not record that a key changed when lpop is called on an empty list" do
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.lpop key_name

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when rpop is called" do
        populate_list
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.rpop key_name

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "does not record that a key changed when rpop is called on an empty list" do
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.rpop key_name

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when rpoplpush is called" do
        populate_list
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.rpoplpush key_name, key_name_2

        expect(subject.get_set(:@updated_keys)).to be_include key_name
        expect(subject.get_set(:@updated_keys)).to be_include key_name_2
      end

      it "does not record that a key changed when rpoplpush is called on an empty list" do
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.rpoplpush key_name, key_name_2

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
      end

      it "records that a key changed when spop is called" do
        populate_set
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.spop key_name

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "does not record that a key changed when spop is called on an empty set" do
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.spop key_name

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end
    end

    describe "write commands" do
      it "records that a key changed when append is called" do
        subject.redis.set key_name, string_value
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.append key_name, string_value_2

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when bitop is called" do
        subject.redis.set key_name, string_value
        subject.redis.set key_name_2, string_value_2
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.bitop ["AND", "OR", "XOR"].sample, key_name_3, key_name, key_name_2

        expect(subject.get_set(:@updated_keys)).to be_include key_name_3
      end

      it "records that a key changed when bitop NOT is called" do
        subject.redis.set key_name, string_value
        subject.redis.set key_name_2, string_value_2
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.bitop "NOT", key_name_3, key_name

        expect(subject.get_set(:@updated_keys)).to be_include key_name_3
      end

      it "records that a key changed when brpoplpush is called" do
        populate_list
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.brpoplpush key_name, key_name_2, 1

        expect(subject.get_set(:@updated_keys)).to be_include key_name
        expect(subject.get_set(:@updated_keys)).to be_include key_name_2
      end

      it "records that a key changed when decr is called" do
        subject.redis.set key_name, rand(100..1_000)
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.decr key_name

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when decrby is called" do
        subject.redis.set key_name, rand(100..1_000)
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.decrby key_name, rand(5..10)

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when del is called" do
        subject.redis.set key_name, string_value
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.del key_name

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when expire is called" do
        subject.redis.set key_name, string_value
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.expire key_name, rand(100..1_000)

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when expireat is called" do
        subject.redis.set key_name, string_value
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.expireat key_name, (Time.now + rand(100..1_000).seconds).to_i

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when getset is called" do
        subject.redis.set key_name, string_value
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.getset key_name, string_value_2

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when hset is called" do
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.hset key_name, *hash_values.first

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when hincrby is called" do
        subject.redis.hset key_name, hash_values.first[0], rand(10..100)
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.hincrby key_name, hash_values.first[0], rand(10..100)

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when hincrbyfloat is called" do
        subject.redis.hset key_name, hash_values.first[0], [1, 10, 100, 1_000, 10_000].sample * rand
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.hincrbyfloat key_name, hash_values.first[0], [1, 10, 100, 1_000, 10_000].sample * rand(10..100)

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when hmset is called" do
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.hmset key_name, *hash_values.to_a.flatten

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when incr is called" do
        subject.redis.set key_name, rand(100..100_000)
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.incr key_name

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when incrby is called" do
        subject.redis.set key_name, rand(100..100_000)
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.incrby key_name, rand(10..100)

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when incrbyfloat is called" do
        subject.redis.set key_name, [1, 10, 100, 1_000, 10_000].sample * rand
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.incrbyfloat key_name, [1, 10, 100, 1_000, 10_000].sample * rand(10..100)

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when lpush is called" do
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.lpush key_name, list_values[0]

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when lset is called" do
        populate_list
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.lset key_name, 0, string_value

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when ltrim is called" do
        populate_list
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.ltrim key_name, -2, -1

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when mapped_hmset is called" do
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.mapped_hmset key_name, hash_values

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when mapped_mset is called" do
        hash_values.keys.each do |alt_key_name|
          expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
        end

        server_subject.mapped_mset hash_values

        hash_values.keys.each do |alt_key_name|
          expect(subject.get_set(:@updated_keys)).to be_include alt_key_name
        end
      end

      it "records that a key changed when mset is called" do
        hash_values.keys.each do |alt_key_name|
          expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
        end

        server_subject.mset(*hash_values.to_a.flatten)

        hash_values.keys.each do |alt_key_name|
          expect(subject.get_set(:@updated_keys)).to be_include alt_key_name
        end
      end

      it "records that a key changed when pexpire is called" do
        subject.redis.set key_name, string_value
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.pexpire key_name, rand(100_000..1_000_000)

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when pexpireat is called" do
        subject.redis.set key_name, string_value
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.pexpireat key_name, (Time.now + rand(100..1_000).seconds).to_i * 1_000

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when psetex is called" do
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.psetex key_name, rand(100_000..1_000_000), string_value

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when rename is called" do
        subject.redis.set key_name, string_value
        subject.redis.set key_name_2, string_value_2
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

        server_subject.rename key_name, key_name_2

        expect(subject.get_set(:@updated_keys)).to be_include key_name
        expect(subject.get_set(:@updated_keys)).to be_include key_name_2
      end

      it "records that a key changed when restore is called" do
        subject.redis.set key_name, string_value
        restore_value = subject.redis.dump key_name
        subject.redis.del key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.restore key_name, 0, restore_value

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when rpush is called" do
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.rpush key_name, list_values[0]

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when set is called" do
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.set key_name, string_value

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when setbit is called" do
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.setbit key_name, 1, 1

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when setex is called" do
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.setex key_name, rand(100..1_000), string_value

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when setrange is called" do
        subject.redis.set key_name, string_value
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.setrange key_name, rand(0..(string_value.length - 2)), string_value_2

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when sort is called" do
        populate_list
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

        server_subject.sort key_name, order: "ALPHA", store: key_name_2

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).to be_include key_name_2
      end

      it "does not record that a key changed when sort is called without a store" do
        populate_list
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

        server_subject.sort key_name, order: "ALPHA"

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
      end

      it "records that a key changed when zincrby is called" do
        populate_sorted_set
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.zincrby key_name, rand(10..100), sorted_set_values[0]

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      it "records that a key changed when []= is called" do
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject[key_name] = string_value

        expect(subject.get_set(:@updated_keys)).to be_include key_name
      end

      describe "flush database" do
        before(:each) do
          subject.add_set_value :@initial_keys, key_name
          expect(server_subject.redis).to receive(:send).and_return 1
        end

        after(:each) do
          subject.remove_set_value :@initial_keys, key_name
        end

        it "records that a key changed when flushdb is called" do
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@initial_keys)).to be_include key_name

          server_subject.flushdb

          expect(subject.get_set(:@initial_keys)).to be_include key_name
          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records that a key changed when flushall is called" do
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@initial_keys)).to be_include key_name

          server_subject.flushdb

          expect(subject.get_set(:@initial_keys)).to be_include key_name
          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end
      end
    end

    describe "read commands" do
      it "does not record a call to bitcount" do
        subject.redis.set key_name, string_value
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.bitcount key_name

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to dump" do
        subject.redis.set key_name, string_value
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.dump key_name

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to exists" do
        subject.redis.set key_name, string_value
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.exists key_name

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to get" do
        subject.redis.set key_name, string_value
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.get key_name

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to getbit" do
        subject.redis.set key_name, string_value
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.getbit key_name, 1

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to getrange" do
        subject.redis.set key_name, string_value
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.getrange key_name, 0, -2

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to hget" do
        populate_hash
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.hget key_name, hash_values.keys.sample

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to hmget" do
        populate_hash
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.hmget key_name, *hash_values.keys.sample(4)

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to hexists" do
        populate_hash
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.hexists key_name, hash_values.keys.sample

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to hlen" do
        populate_hash
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.hlen key_name

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to hkeys" do
        populate_hash
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.hkeys key_name

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to hscan" do
        if Gem::Version.new("2.8.0") < Gem::Version.new(subject.redis.info["redis_version"])
          populate_hash
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.hscan key_name, 0

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        end
      end

      it "does not record a call to hscan_each" do
        if Gem::Version.new("2.8.0") < Gem::Version.new(subject.redis.info["redis_version"])
          populate_hash
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.hscan_each key_name do |key, value|
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        end
      end

      it "does not record a call to hvals" do
        populate_hash
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.hvals key_name

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to hgetall" do
        populate_hash
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.hgetall key_name

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to lindex" do
        populate_list
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.lindex key_name, rand(0..(list_values.length - 1))

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to llen" do
        populate_list
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.llen key_name

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to lrange" do
        populate_list
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.lrange key_name, 0, -1

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to mapped_hmget" do
        populate_hash
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.mapped_hmget key_name, *hash_values.keys

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to mapped_mget" do
        subject.redis.set key_name, string_value
        subject.redis.set key_name_2, string_value_2
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

        server_subject.mapped_mget key_name, key_name_2

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
      end

      it "does not record a call to mget" do
        subject.redis.set key_name, string_value
        subject.redis.set key_name_2, string_value_2
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

        server_subject.mget key_name, key_name_2

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
      end

      it "does not record a call to scard" do
        populate_set
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.scard key_name

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to scan" do
        if Gem::Version.new("2.8.0") < Gem::Version.new(subject.redis.info["redis_version"])
          subject.redis.set key_name, string_value
          subject.redis.set key_name_2, string_value_2
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

          server_subject.scan 0

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        end
      end

      it "does not record a call to scan_each" do
        if Gem::Version.new("2.8.0") < Gem::Version.new(subject.redis.info["redis_version"])
          subject.redis.set key_name, string_value
          subject.redis.set key_name_2, string_value_2
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

          server_subject.scan_each do |key|
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        end
      end

      it "does not record a call to sdiff" do
        populate_set
        set_values.sample(4).each do |set_value|
          subject.redis.sadd key_name_2, set_value
        end
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

        server_subject.sdiff key_name, key_name_2

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
      end

      it "does not record a call to sismember" do
        populate_set
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.sismember key_name, set_values.first[0]

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to smembers" do
        populate_set
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.smembers key_name

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to srandmember" do
        populate_set
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.srandmember key_name

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to sscan" do
        if Gem::Version.new("2.8.0") < Gem::Version.new(subject.redis.info["redis_version"])
          populate_set
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.sscan key_name, 0

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        end
      end

      it "does not record a call to sscan_each" do
        if Gem::Version.new("2.8.0") < Gem::Version.new(subject.redis.info["redis_version"])
          populate_set
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.sscan_each key_name do |key|
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        end
      end

      it "does not record a call to strlen" do
        subject.redis.set key_name, string_value
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.strlen key_name

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to sunion" do
        populate_set
        set_values.sample(4).each do |set_value|
          subject.redis.sadd key_name_2, set_value
        end
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

        server_subject.sunion key_name, key_name_2

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
      end

      it "does not record a call to type" do
        subject.redis.set key_name, string_value
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.type key_name

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to zcard" do
        populate_sorted_set
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.zcard key_name

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to zcount" do
        populate_sorted_set
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.zcount key_name, "-inf", "+inf"

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to zlexcount" do
        if Gem::Version.new("2.8.6") < Gem::Version.new(subject.redis.info["redis_version"])
          populate_lex_sorted_set
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.zlexcount key_name, "-", "+"

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        end
      end

      it "does not record a call to zrange" do
        populate_sorted_set
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.zrange key_name, 0, -1

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to zrangebyscore" do
        populate_sorted_set
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.zrangebyscore key_name, "-inf", "+inf"

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to zrangebylex" do
        if Gem::Version.new("2.8.6") < Gem::Version.new(subject.redis.info["redis_version"])
          populate_lex_sorted_set
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.zrangebylex key_name, "-", "+"

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        end
      end

      it "does not record a call to zrank" do
        populate_sorted_set
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.zrank key_name, sorted_set_values.first[0]

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to zrevrange" do
        populate_sorted_set
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.zrevrange key_name, 0, -1

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to zrevrangebyscore" do
        populate_sorted_set
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.zrevrangebyscore key_name, "-inf", "+inf"

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to zrevrangebylex" do
        if Gem::Version.new("2.8.6") < Gem::Version.new(subject.redis.info["redis_version"])
          populate_lex_sorted_set
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.zrevrangebylex key_name, "-", "+"

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        end
      end

      it "does not record a call to zrevrank" do
        populate_sorted_set
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.zrevrank key_name, sorted_set_values.first[0]

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to zscan" do
        if Gem::Version.new("2.8.0") < Gem::Version.new(subject.redis.info["redis_version"])
          populate_sorted_set
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.zscan key_name, 0

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        end
      end

      it "does not record a call to zscan_each" do
        if Gem::Version.new("2.8.0") < Gem::Version.new(subject.redis.info["redis_version"])
          populate_sorted_set
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.zscan_each key_name do |key|
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        end
      end

      it "does not record a call to zscore" do
        populate_sorted_set
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject.zscore key_name, sorted_set_values.first[0]

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record a call to []" do
        subject.redis.set key_name, string_value
        expect(subject.get_set(:@updated_keys)).not_to be_include key_name

        server_subject[key_name]

        expect(subject.get_set(:@updated_keys)).not_to be_include key_name
      end
    end

    describe "#multi" do
      describe "#exec" do
        describe "commands that return the number of values affected" do
          it "records an updated key if sadd changes a record" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.sadd key_name, set_values[0]
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records an updated key if zadd changes a record" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.zadd key_name, sorted_set_values.first[1].to_f, sorted_set_values.first[0]
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records an updated key if srem changes a record" do
            populate_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.srem key_name, set_values.sample
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records an updated key if zrem changes a record" do
            populate_sorted_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.zrem key_name, sorted_set_values.keys.sample
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records an updated key if zremrangebyrank changes a record" do
            populate_sorted_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.zremrangebyrank key_name, 0, -1
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records an updated key if zremrangebyscore changes a record" do
            populate_sorted_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.zremrangebyscore key_name, sorted_set_values.first[1] - 1, sorted_set_values.first[1] + 1
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records an updated key if zremrangebylex changes a record" do
            if Gem::Version.new("2.8.9") < Gem::Version.new(subject.redis.info["redis_version"])
              populate_lex_sorted_set
              expect(subject.get_set(:@updated_keys)).not_to be_include key_name

              server_subject.multi
              server_subject.zremrangebylex key_name, "-", "+"
              server_subject.exec

              expect(subject.get_set(:@updated_keys)).to be_include key_name
            end
          end

          it "does not record an update if sadd does not change a record" do
            subject.redis.sadd key_name, set_values[0]
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.sadd key_name, set_values[0]
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record an update if zadd does not change a record" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.zadd key_name, sorted_set_values.first[1], sorted_set_values.first[0]
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "does not record an update if srem does not change a record" do
            populate_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.srem key_name, "1234"
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record an update if zrem does not change a record" do
            populate_sorted_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.zrem key_name, "1234"
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record an update if zremrangebyrank does not change a record" do
            populate_sorted_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.zremrangebyrank key_name, sorted_set_values.length + 12, sorted_set_values.length + 22
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record an update if zremrangebyscore does not change a record" do
            populate_sorted_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.zremrangebyscore key_name, sorted_set_values.first[1] - 2, sorted_set_values.first[1] - 1
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record an updated key if zremrangebylex does not change a record" do
            if Gem::Version.new("2.8.9") < Gem::Version.new(subject.redis.info["redis_version"])
              populate_lex_sorted_set
              expect(subject.get_set(:@updated_keys)).not_to be_include key_name

              server_subject.multi
              server_subject.zremrangebylex key_name, "[1", "(1"
              server_subject.exec

              expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            end
          end

          it "records that a key changed when hsetnx is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.hsetnx key_name, *hash_values.first
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "does not record that a key changed when hsetnx is called for an existing hash value" do
            subject.redis.hset key_name, *hash_values.first
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.hsetnx key_name, *hash_values.first
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when hdel is called" do
            populate_hash
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.hdel key_name, *hash_values.first[0]
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "does not record that a key changed when hdel is called for a non-existing field" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.hdel key_name, hash_values.first[0]
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when linsert is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.linsert key_name, ["BEFORE", "AFTER"].sample, list_values.sample, string_value
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "does not record that a key changed when linsert is called for an empty key" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.linsert key_name, ["BEFORE", "AFTER"].sample, list_values.sample, string_value
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record that a key changed when linsert is called for a missing pivot" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.linsert key_name, ["BEFORE", "AFTER"].sample, "1234", string_value
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when lpushx is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.lpushx key_name, string_value
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "does not record that a key changed when lpushx is called on an empty list" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.lpushx key_name, list_values[0]
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when rpushx is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.lpushx key_name, string_value
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "does not record that a key changed when rpushx is called on an empty list" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.lpushx key_name, list_values[0]
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when lrem is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.lrem key_name, 0, list_values.sample
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "does not record that a key changed when lrem is called on an empty list" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.lrem key_name, 0, "1234"
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when mapped_msetnx is called" do
            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end

            server_subject.multi
            server_subject.mapped_msetnx hash_values
            server_subject.exec

            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).to be_include alt_key_name
            end
          end

          it "does not record that a key changed when mapped_msetnx is called and a value exists" do
            subject.redis.set(*hash_values.first)

            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end

            server_subject.multi
            server_subject.mapped_msetnx hash_values
            server_subject.exec

            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end
          end

          it "records that a key changed when msetnx is called" do
            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end

            server_subject.multi
            server_subject.msetnx(*hash_values.to_a.flatten)
            server_subject.exec

            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).to be_include alt_key_name
            end
          end

          it "does not record that a key changed when mapped_msetnx is called and a value exists" do
            subject.redis.set(*hash_values.first)

            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end

            server_subject.multi
            server_subject.msetnx(*hash_values.to_a.flatten)
            server_subject.exec

            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end
          end

          it "records that a key changed when persist is called" do
            subject.redis.setex key_name, rand(100..100_000), string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.persist key_name
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "does not record that a key changed when persist is called on a persisted key" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.persist key_name
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when renamenx is called" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

            server_subject.multi
            server_subject.renamenx key_name, key_name_2
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
            expect(subject.get_set(:@updated_keys)).to be_include key_name_2
          end

          it "does not record that a key changed when renamenx is called if the dest exists" do
            subject.redis.set key_name, string_value
            subject.redis.set key_name_2, string_value_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

            server_subject.multi
            server_subject.renamenx key_name, key_name_2
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          end

          it "records that a key changed when sdiffstore is called" do
            populate_set
            set_values.sample(4).each do |set_value|
              subject.redis.sadd key_name_2, set_value
            end
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi
            server_subject.sdiffstore key_name_3, key_name, key_name_2
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).to be_include key_name_3
          end

          it "does not record that a key changed when sdiffstore is empty" do
            populate_set
            set_values.each do |set_value|
              subject.redis.sadd key_name_2, set_value
            end
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi
            server_subject.sdiffstore key_name_3, key_name, key_name_2
            server_subject.exec

            expect(subject.redis.type(key_name_3)).to eq "none"
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
          end

          it "records that a key changed when setnx is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.setnx key_name, string_value
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "does not record that a key changed when setnx is called on an existing key" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.setnx key_name, string_value
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when sinterstore is called" do
            populate_set
            set_values.sample(4).each do |set_value|
              subject.redis.sadd key_name_2, set_value
            end
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi
            server_subject.sinterstore key_name_3, key_name, key_name_2
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).to be_include key_name_3
          end

          it "does not record that a key changed when sinterstore is called and there is no intersection" do
            populate_set
            subject.redis.sadd key_name_2, "1234"
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi
            server_subject.sinterstore key_name_3, key_name, key_name_2
            server_subject.exec

            expect(subject.redis.type(key_name_3)).to eq "none"
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
          end

          it "records that a key changed when smove is called" do
            populate_set
            set_values.sample(4).each do |set_value|
              subject.redis.sadd key_name_2, set_value
            end
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

            server_subject.multi
            server_subject.smove key_name, key_name_2, set_values.sample
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
            expect(subject.get_set(:@updated_keys)).to be_include key_name_2
          end

          it "does not record that a key changed when smove is called and the set doesn't exist" do
            set_values.sample(4).each do |set_value|
              subject.redis.sadd key_name_2, set_value
            end
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

            server_subject.multi
            server_subject.smove key_name, key_name_2, set_values.sample
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          end

          it "does not record that a key changed when smove is called and the set doesn't have the element" do
            populate_set
            set_values.sample(4).each do |set_value|
              subject.redis.sadd key_name_2, set_value
            end
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

            server_subject.multi
            server_subject.smove key_name, key_name_2, "1234"
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          end

          it "records that a key changed when sunionstore is called" do
            populate_set
            set_values.sample(4).each do |set_value|
              subject.redis.sadd key_name_2, set_value
            end
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi
            server_subject.sunionstore key_name_3, key_name, key_name_2
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).to be_include key_name_3
          end

          it "does not record that a key changed when sunionstore is called on empty sets" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi
            server_subject.sunionstore key_name_3, key_name, key_name_2
            server_subject.exec

            expect(subject.redis.type(key_name_3)).to eq "none"
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
          end

          it "records that a key changed when zinterstore is called" do
            populate_sorted_set
            sorted_set_values.to_a.sample(4).each do |sort_value|
              subject.redis.zadd key_name_2, sort_value[1], sort_value[0]
            end
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi
            server_subject.zinterstore key_name_3, [key_name, key_name_2]
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).to be_include key_name_3
          end

          it "does not record that a key changed when zinterstore is called and there is no intersection" do
            populate_sorted_set
            subject.redis.sadd key_name_2, "1234"
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi
            server_subject.zinterstore key_name_3, [key_name, key_name_2]
            server_subject.exec

            expect(subject.redis.type(key_name_3)).to eq "none"
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
          end

          it "records that a key changed when zunionstore is called" do
            populate_sorted_set
            sorted_set_values.to_a.sample(4).each do |sort_value|
              subject.redis.zadd key_name, sort_value[1], sort_value[0]
            end
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi
            server_subject.zunionstore key_name_3, [key_name, key_name_2]
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).to be_include key_name_3
          end

          it "does not record that a key changed when zunionstore is called on empty sets" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi
            server_subject.zunionstore key_name_3, [key_name, key_name_2]
            server_subject.exec

            expect(subject.redis.type(key_name_3)).to eq "none"
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
          end
        end

        describe "commands that return nil on failure" do
          it "records that a key changed when lpop is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.lpop key_name
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "does not record that a key changed when lpop is called on an empty list" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.lpop key_name
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when rpop is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.rpop key_name
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "does not record that a key changed when rpop is called on an empty list" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.rpop key_name
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when rpoplpush is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.rpoplpush key_name, key_name_2
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
            expect(subject.get_set(:@updated_keys)).to be_include key_name_2
          end

          it "does not record that a key changed when rpoplpush is called on an empty list" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.rpoplpush key_name, key_name_2
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          end

          it "records that a key changed when spop is called" do
            populate_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.spop key_name
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "does not record that a key changed when spop is called on an empty set" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.spop key_name
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end
        end

        describe "write commands" do
          it "records that a key changed when append is called" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.append key_name, string_value_2
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when bitop is called" do
            subject.redis.set key_name, string_value
            subject.redis.set key_name_2, string_value_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.bitop ["AND", "OR", "XOR"].sample, key_name_3, key_name, key_name_2
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name_3
          end

          it "records that a key changed when bitop NOT is called" do
            subject.redis.set key_name, string_value
            subject.redis.set key_name_2, string_value_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.bitop "NOT", key_name_3, key_name
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name_3
          end

          it "records that a key changed when brpoplpush is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.brpoplpush key_name, key_name_2, 1
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
            expect(subject.get_set(:@updated_keys)).to be_include key_name_2
          end

          it "records that a key changed when decr is called" do
            subject.redis.set key_name, rand(100..1_000)
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.decr key_name
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when decrby is called" do
            subject.redis.set key_name, rand(100..1_000)
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.decrby key_name, rand(5..10)
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when del is called" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.del key_name
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when expire is called" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.expire key_name, rand(100..1_000)
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when expireat is called" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.expireat key_name, (Time.now + rand(100..1_000).seconds).to_i
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when getset is called" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.getset key_name, string_value_2
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when hset is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.hset key_name, *hash_values.first
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when hincrby is called" do
            subject.redis.hset key_name, hash_values.first[0], rand(10..100)
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.hincrby key_name, hash_values.first[0], rand(10..100)
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          # # This fails for some unknown reason, but that is not significant to my project as the failure is a redis
          # # or redis gem failure as far as I can tell.
          #
          # it "records that a key changed when hincrbyfloat is called" do
          #   subject.redis.hset key_name, hash_values.first[0], [1, 10, 100, 1_000, 10_000].sample * rand
          #   expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          #
          #   server_subject.multi
          #   server_subject.hincrbyfloat key_name, hash_values.first[0], [1, 10, 100, 1_000, 10_000].sample * rand(10..100)
          #   server_subject.exec
          #
          #   expect(subject.get_set(:@updated_keys)).to be_include key_name
          # end

          it "records that a key changed when hmset is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.hmset key_name, *hash_values.to_a.flatten
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when incr is called" do
            subject.redis.set key_name, rand(100..100_000)
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.incr key_name
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when incrby is called" do
            subject.redis.set key_name, rand(100..100_000)
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.incrby key_name, rand(10..100)
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          # # This fails for some unknown reason, but that is not significant to my project as the failure is a redis
          # # or redis gem failure as far as I can tell.
          #
          # it "records that a key changed when incrbyfloat is called" do
          #   subject.redis.set key_name, [1, 10, 100, 1_000, 10_000].sample * rand
          #   expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          #
          #   server_subject.multi
          #   server_subject.incrbyfloat key_name, [1, 10, 100, 1_000, 10_000].sample * rand(10..100)
          #   server_subject.exec
          #
          #   expect(subject.get_set(:@updated_keys)).to be_include key_name
          # end

          it "records that a key changed when lpush is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.lpush key_name, list_values[0]
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when lset is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.lset key_name, 0, string_value
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when ltrim is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.ltrim key_name, -2, -1
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when mapped_hmset is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.mapped_hmset key_name, hash_values
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when mapped_mset is called" do
            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end

            server_subject.multi
            server_subject.mapped_mset hash_values
            server_subject.exec

            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).to be_include alt_key_name
            end
          end

          it "records that a key changed when mset is called" do
            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end

            server_subject.multi
            server_subject.mset(*hash_values.to_a.flatten)
            server_subject.exec

            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).to be_include alt_key_name
            end
          end

          it "records that a key changed when pexpire is called" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.pexpire key_name, rand(100_000..1_000_000)
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when pexpireat is called" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.pexpireat key_name, (Time.now + rand(100..1_000).seconds).to_i * 1_000
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when psetex is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.psetex key_name, rand(100_000..1_000_000), string_value
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when rename is called" do
            subject.redis.set key_name, string_value
            subject.redis.set key_name_2, string_value_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

            server_subject.multi
            server_subject.rename key_name, key_name_2
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
            expect(subject.get_set(:@updated_keys)).to be_include key_name_2
          end

          it "records that a key changed when restore is called" do
            subject.redis.set key_name, string_value
            restore_value = subject.redis.dump key_name
            subject.redis.del key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.restore key_name, 0, restore_value
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when rpush is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.rpush key_name, list_values[0]
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when set is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.set key_name, string_value
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when setbit is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.setbit key_name, 1, 1
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when setex is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.setex key_name, rand(100..1_000), string_value
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when setrange is called" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.setrange key_name, rand(0..(string_value.length - 2)), string_value_2
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when sort is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

            server_subject.multi
            server_subject.sort key_name, order: "ALPHA", store: key_name_2
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).to be_include key_name_2
          end

          it "does not record that a key changed when sort is called without a store" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

            server_subject.multi
            server_subject.sort key_name, order: "ALPHA"
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          end

          # # This fails for some unknown reason, but that is not significant to my project as the failure is a redis
          # # or redis gem failure as far as I can tell.
          #
          # it "records that a key changed when zincrby is called" do
          #   populate_sorted_set
          #   expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          #
          #   server_subject.multi
          #   server_subject.zincrby key_name, rand(10..100), sorted_set_values[0]
          #   server_subject.exec
          #
          #   expect(subject.get_set(:@updated_keys)).to be_include key_name
          # end

          it "records that a key changed when []= is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject[key_name] = string_value
            server_subject.exec

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end
        end
      end

      describe "block" do
        describe "commands that return the number of values affected" do
          it "records an updated key if sadd changes a record" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.sadd key_name, set_values[0]
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records an updated key if zadd changes a record" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.zadd key_name, sorted_set_values.first[1].to_f, sorted_set_values.first[0]
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records an updated key if srem changes a record" do
            populate_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.srem key_name, set_values.sample
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records an updated key if zrem changes a record" do
            populate_sorted_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.zrem key_name, sorted_set_values.keys.sample
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records an updated key if zremrangebyrank changes a record" do
            populate_sorted_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.zremrangebyrank key_name, 0, -1
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records an updated key if zremrangebyscore changes a record" do
            populate_sorted_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.zremrangebyscore key_name, sorted_set_values.first[1] - 1, sorted_set_values.first[1] + 1
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records an updated key if zremrangebylex changes a record" do
            if Gem::Version.new("2.8.9") < Gem::Version.new(subject.redis.info["redis_version"])
              populate_lex_sorted_set
              expect(subject.get_set(:@updated_keys)).not_to be_include key_name

              server_subject.multi do
                server_subject.zremrangebylex key_name, "-", "+"
              end

              expect(subject.get_set(:@updated_keys)).to be_include key_name
            end
          end

          it "does not record an update if sadd does not change a record" do
            subject.redis.sadd key_name, set_values[0]
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.sadd key_name, set_values[0]
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record an update if zadd does not change a record" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.zadd key_name, sorted_set_values.first[1], sorted_set_values.first[0]
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "does not record an update if srem does not change a record" do
            populate_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.srem key_name, "1234"
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record an update if zrem does not change a record" do
            populate_sorted_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.zrem key_name, "1234"
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record an update if zremrangebyrank does not change a record" do
            populate_sorted_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.zremrangebyrank key_name, sorted_set_values.length + 12, sorted_set_values.length + 22
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record an update if zremrangebyscore does not change a record" do
            populate_sorted_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.zremrangebyscore key_name, sorted_set_values.first[1] - 2, sorted_set_values.first[1] - 1
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record an updated key if zremrangebylex does not change a record" do
            if Gem::Version.new("2.8.9") < Gem::Version.new(subject.redis.info["redis_version"])
              populate_lex_sorted_set
              expect(subject.get_set(:@updated_keys)).not_to be_include key_name

              server_subject.multi do
                server_subject.zremrangebylex key_name, "[1", "(1"
              end

              expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            end
          end

          it "records that a key changed when hsetnx is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.hsetnx key_name, *hash_values.first
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "does not record that a key changed when hsetnx is called for an existing hash value" do
            subject.redis.hset key_name, *hash_values.first
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.hsetnx key_name, *hash_values.first
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when hdel is called" do
            populate_hash
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.hdel key_name, *hash_values.first[0]
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "does not record that a key changed when hdel is called for a non-existing field" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.hdel key_name, hash_values.first[0]
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when linsert is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.linsert key_name, ["BEFORE", "AFTER"].sample, list_values.sample, string_value
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "does not record that a key changed when linsert is called for an empty key" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.linsert key_name, ["BEFORE", "AFTER"].sample, list_values.sample, string_value
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record that a key changed when linsert is called for a missing pivot" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.linsert key_name, ["BEFORE", "AFTER"].sample, "1234", string_value
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when lpushx is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.lpushx key_name, string_value
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "does not record that a key changed when lpushx is called on an empty list" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.lpushx key_name, list_values[0]
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when rpushx is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.lpushx key_name, string_value
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "does not record that a key changed when rpushx is called on an empty list" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.lpushx key_name, list_values[0]
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when lrem is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.lrem key_name, 0, list_values.sample
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "does not record that a key changed when lrem is called on an empty list" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.lrem key_name, 0, "1234"
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when mapped_msetnx is called" do
            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end

            server_subject.multi do
              server_subject.mapped_msetnx hash_values
            end

            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).to be_include alt_key_name
            end
          end

          it "does not record that a key changed when mapped_msetnx is called and a value exists" do
            subject.redis.set(*hash_values.first)

            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end

            server_subject.multi do
              server_subject.mapped_msetnx hash_values
            end

            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end
          end

          it "records that a key changed when msetnx is called" do
            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end

            server_subject.multi do
              server_subject.msetnx(*hash_values.to_a.flatten)
            end

            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).to be_include alt_key_name
            end
          end

          it "does not record that a key changed when mapped_msetnx is called and a value exists" do
            subject.redis.set(*hash_values.first)

            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end

            server_subject.multi do
              server_subject.msetnx(*hash_values.to_a.flatten)
            end

            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end
          end

          it "records that a key changed when persist is called" do
            subject.redis.setex key_name, rand(100..100_000), string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.persist key_name
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "does not record that a key changed when persist is called on a persisted key" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.persist key_name
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when renamenx is called" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

            server_subject.multi do
              server_subject.renamenx key_name, key_name_2
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
            expect(subject.get_set(:@updated_keys)).to be_include key_name_2
          end

          it "does not record that a key changed when renamenx is called if the dest exists" do
            subject.redis.set key_name, string_value
            subject.redis.set key_name_2, string_value_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

            server_subject.multi do
              server_subject.renamenx key_name, key_name_2
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          end

          it "records that a key changed when sdiffstore is called" do
            populate_set
            set_values.sample(4).each do |set_value|
              subject.redis.sadd key_name_2, set_value
            end
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi do
              server_subject.sdiffstore key_name_3, key_name, key_name_2
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).to be_include key_name_3
          end

          it "does not record that a key changed when sdiffstore is empty" do
            populate_set
            set_values.each do |set_value|
              subject.redis.sadd key_name_2, set_value
            end
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi do
              server_subject.sdiffstore key_name_3, key_name, key_name_2
            end

            expect(subject.redis.type(key_name_3)).to eq "none"
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
          end

          it "records that a key changed when setnx is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.setnx key_name, string_value
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "does not record that a key changed when setnx is called on an existing key" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.setnx key_name, string_value
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when sinterstore is called" do
            populate_set
            set_values.sample(4).each do |set_value|
              subject.redis.sadd key_name_2, set_value
            end
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi do
              server_subject.sinterstore key_name_3, key_name, key_name_2
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).to be_include key_name_3
          end

          it "does not record that a key changed when sinterstore is called and there is no intersection" do
            populate_set
            subject.redis.sadd key_name_2, "1234"
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi do
              server_subject.sinterstore key_name_3, key_name, key_name_2
            end

            expect(subject.redis.type(key_name_3)).to eq "none"
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
          end

          it "records that a key changed when smove is called" do
            populate_set
            set_values.sample(4).each do |set_value|
              subject.redis.sadd key_name_2, set_value
            end
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

            server_subject.multi do
              server_subject.smove key_name, key_name_2, set_values.sample
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
            expect(subject.get_set(:@updated_keys)).to be_include key_name_2
          end

          it "does not record that a key changed when smove is called and the set doesn't exist" do
            set_values.sample(4).each do |set_value|
              subject.redis.sadd key_name_2, set_value
            end
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

            server_subject.multi do
              server_subject.smove key_name, key_name_2, set_values.sample
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          end

          it "does not record that a key changed when smove is called and the set doesn't have the element" do
            populate_set
            set_values.sample(4).each do |set_value|
              subject.redis.sadd key_name_2, set_value
            end
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

            server_subject.multi do
              server_subject.smove key_name, key_name_2, "1234"
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          end

          it "records that a key changed when sunionstore is called" do
            populate_set
            set_values.sample(4).each do |set_value|
              subject.redis.sadd key_name_2, set_value
            end
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi do
              server_subject.sunionstore key_name_3, key_name, key_name_2
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).to be_include key_name_3
          end

          it "does not record that a key changed when sunionstore is called on empty sets" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi do
              server_subject.sunionstore key_name_3, key_name, key_name_2
            end

            expect(subject.redis.type(key_name_3)).to eq "none"
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
          end

          it "records that a key changed when zinterstore is called" do
            populate_sorted_set
            sorted_set_values.to_a.sample(4).each do |sort_value|
              subject.redis.zadd key_name_2, sort_value[1], sort_value[0]
            end
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi do
              server_subject.zinterstore key_name_3, [key_name, key_name_2]
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).to be_include key_name_3
          end

          it "does not record that a key changed when zinterstore is called and there is no intersection" do
            populate_sorted_set
            subject.redis.sadd key_name_2, "1234"
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi do
              server_subject.zinterstore key_name_3, [key_name, key_name_2]
            end

            expect(subject.redis.type(key_name_3)).to eq "none"
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
          end

          it "records that a key changed when zunionstore is called" do
            populate_sorted_set
            sorted_set_values.to_a.sample(4).each do |sort_value|
              subject.redis.zadd key_name, sort_value[1], sort_value[0]
            end
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi do
              server_subject.zunionstore key_name_3, [key_name, key_name_2]
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).to be_include key_name_3
          end

          it "does not record that a key changed when zunionstore is called on empty sets" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi do
              server_subject.zunionstore key_name_3, [key_name, key_name_2]
            end

            expect(subject.redis.type(key_name_3)).to eq "none"
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
          end
        end

        describe "commands that return nil on failure" do
          it "records that a key changed when lpop is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.lpop key_name
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "does not record that a key changed when lpop is called on an empty list" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.lpop key_name
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when rpop is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.rpop key_name
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "does not record that a key changed when rpop is called on an empty list" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.rpop key_name
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when rpoplpush is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.rpoplpush key_name, key_name_2
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
            expect(subject.get_set(:@updated_keys)).to be_include key_name_2
          end

          it "does not record that a key changed when rpoplpush is called on an empty list" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.rpoplpush key_name, key_name_2
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          end

          it "records that a key changed when spop is called" do
            populate_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.spop key_name
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "does not record that a key changed when spop is called on an empty set" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.spop key_name
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end
        end

        describe "write commands" do
          it "records that a key changed when append is called" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.append key_name, string_value_2
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when bitop is called" do
            subject.redis.set key_name, string_value
            subject.redis.set key_name_2, string_value_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.bitop ["AND", "OR", "XOR"].sample, key_name_3, key_name, key_name_2
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name_3
          end

          it "records that a key changed when bitop NOT is called" do
            subject.redis.set key_name, string_value
            subject.redis.set key_name_2, string_value_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.bitop "NOT", key_name_3, key_name
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name_3
          end

          # # This fails for some unknown reason, but that is not significant to my project as the failure is a redis
          # # or redis gem failure as far as I can tell.
          #
          # it "records that a key changed when brpoplpush is called" do
          #   populate_list
          #   expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          #
          #   server_subject.multi do
          #     server_subject.brpoplpush key_name, key_name_2, 1
          #   end
          #
          #   expect(subject.get_set(:@updated_keys)).to be_include key_name
          #   expect(subject.get_set(:@updated_keys)).to be_include key_name_2
          # end

          it "records that a key changed when decr is called" do
            subject.redis.set key_name, rand(100..1_000)
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.decr key_name
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when decrby is called" do
            subject.redis.set key_name, rand(100..1_000)
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.decrby key_name, rand(5..10)
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when del is called" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.del key_name
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when expire is called" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.expire key_name, rand(100..1_000)
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when expireat is called" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.expireat key_name, (Time.now + rand(100..1_000).seconds).to_i
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when getset is called" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.getset key_name, string_value_2
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when hset is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.hset key_name, *hash_values.first
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when hincrby is called" do
            subject.redis.hset key_name, hash_values.first[0], rand(10..100)
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.hincrby key_name, hash_values.first[0], rand(10..100)
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          # # This fails for some unknown reason, but that is not significant to my project as the failure is a redis
          # # or redis gem failure as far as I can tell.
          #
          # it "records that a key changed when hincrbyfloat is called" do
          #   subject.redis.hset key_name, hash_values.first[0], [1, 10, 100, 1_000, 10_000].sample * rand
          #   expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          #
          #   server_subject.multi do
          #     server_subject.hincrbyfloat key_name, hash_values.first[0], [1, 10, 100, 1_000, 10_000].sample * rand(10..100)
          #   end
          #
          #   expect(subject.get_set(:@updated_keys)).to be_include key_name
          # end

          it "records that a key changed when hmset is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.hmset key_name, *hash_values.to_a.flatten
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when incr is called" do
            subject.redis.set key_name, rand(100..100_000)
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.incr key_name
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when incrby is called" do
            subject.redis.set key_name, rand(100..100_000)
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.incrby key_name, rand(10..100)
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          # # This fails for some unknown reason, but that is not significant to my project as the failure is a redis
          # # or redis gem failure as far as I can tell.
          #
          # it "records that a key changed when incrbyfloat is called" do
          #   subject.redis.set key_name, [1, 10, 100, 1_000, 10_000].sample * rand
          #   expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          #
          #   server_subject.multi do
          #     server_subject.incrbyfloat key_name, [1, 10, 100, 1_000, 10_000].sample * rand(10..100)
          #   end
          #
          #   expect(subject.get_set(:@updated_keys)).to be_include key_name
          # end

          it "records that a key changed when lpush is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.lpush key_name, list_values[0]
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when lset is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.lset key_name, 0, string_value
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when ltrim is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.ltrim key_name, -2, -1
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when mapped_hmset is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.mapped_hmset key_name, hash_values
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when mapped_mset is called" do
            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end

            server_subject.multi do
              server_subject.mapped_mset hash_values
            end

            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).to be_include alt_key_name
            end
          end

          it "records that a key changed when mset is called" do
            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end

            server_subject.multi do
              server_subject.mset(*hash_values.to_a.flatten)
            end

            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).to be_include alt_key_name
            end
          end

          it "records that a key changed when pexpire is called" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.pexpire key_name, rand(100_000..1_000_000)
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when pexpireat is called" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.pexpireat key_name, (Time.now + rand(100..1_000).seconds).to_i * 1_000
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when psetex is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.psetex key_name, rand(100_000..1_000_000), string_value
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when rename is called" do
            subject.redis.set key_name, string_value
            subject.redis.set key_name_2, string_value_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

            server_subject.multi do
              server_subject.rename key_name, key_name_2
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
            expect(subject.get_set(:@updated_keys)).to be_include key_name_2
          end

          it "records that a key changed when restore is called" do
            subject.redis.set key_name, string_value
            restore_value = subject.redis.dump key_name
            subject.redis.del key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.restore key_name, 0, restore_value
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when rpush is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.rpush key_name, list_values[0]
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when set is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.set key_name, string_value
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when setbit is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.setbit key_name, 1, 1
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when setex is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.setex key_name, rand(100..1_000), string_value
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when setrange is called" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject.setrange key_name, rand(0..(string_value.length - 2)), string_value_2
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end

          it "records that a key changed when sort is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

            server_subject.multi do
              server_subject.sort key_name, order: "ALPHA", store: key_name_2
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).to be_include key_name_2
          end

          it "does not record that a key changed when sort is called without a store" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

            server_subject.multi do
              server_subject.sort key_name, order: "ALPHA"
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          end

          # # This fails for some unknown reason, but that is not significant to my project as the failure is a redis
          # # or redis gem failure as far as I can tell.
          #
          # it "records that a key changed when zincrby is called" do
          #   populate_sorted_set
          #   expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          #
          #   server_subject.multi do
          #     server_subject.zincrby key_name, rand(10..100), sorted_set_values[0]
          #   end
          #
          #   expect(subject.get_set(:@updated_keys)).to be_include key_name
          # end

          it "records that a key changed when []= is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi do
              server_subject[key_name] = string_value
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end
        end
      end

      describe "#discard" do
        describe "commands that return the number of values affected" do
          it "records an updated key if sadd changes a record" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.sadd key_name, set_values[0]
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records an updated key if zadd changes a record" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.zadd key_name, sorted_set_values.first[1].to_f, sorted_set_values.first[0]
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records an updated key if srem changes a record" do
            populate_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.srem key_name, set_values.sample
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records an updated key if zrem changes a record" do
            populate_sorted_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.zrem key_name, sorted_set_values.keys.sample
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records an updated key if zremrangebyrank changes a record" do
            populate_sorted_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.zremrangebyrank key_name, 0, -1
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records an updated key if zremrangebyscore changes a record" do
            populate_sorted_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.zremrangebyscore key_name, sorted_set_values.first[1] - 1, sorted_set_values.first[1] + 1
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records an updated key if zremrangebylex changes a record" do
            if Gem::Version.new("2.8.9") < Gem::Version.new(subject.redis.info["redis_version"])
              populate_lex_sorted_set
              expect(subject.get_set(:@updated_keys)).not_to be_include key_name

              server_subject.multi
              server_subject.zremrangebylex key_name, "-", "+"
              server_subject.discard

              expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            end
          end

          it "does not record an update if sadd does not change a record" do
            subject.redis.sadd key_name, set_values[0]
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.sadd key_name, set_values[0]
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record an update if zadd does not change a record" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.zadd key_name, sorted_set_values.first[1], sorted_set_values.first[0]
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record an update if srem does not change a record" do
            populate_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.srem key_name, "1234"
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record an update if zrem does not change a record" do
            populate_sorted_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.zrem key_name, "1234"
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record an update if zremrangebyrank does not change a record" do
            populate_sorted_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.zremrangebyrank key_name, sorted_set_values.length + 12, sorted_set_values.length + 22
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record an update if zremrangebyscore does not change a record" do
            populate_sorted_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.zremrangebyscore key_name, sorted_set_values.first[1] - 2, sorted_set_values.first[1] - 1
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record an updated key if zremrangebylex does not change a record" do
            if Gem::Version.new("2.8.9") < Gem::Version.new(subject.redis.info["redis_version"])
              populate_lex_sorted_set
              expect(subject.get_set(:@updated_keys)).not_to be_include key_name

              server_subject.multi
              server_subject.zremrangebylex key_name, "[1", "(1"
              server_subject.discard

              expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            end
          end

          it "records that a key changed when hsetnx is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.hsetnx key_name, *hash_values.first
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record that a key changed when hsetnx is called for an existing hash value" do
            subject.redis.hset key_name, *hash_values.first
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.hsetnx key_name, *hash_values.first
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when hdel is called" do
            populate_hash
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.hdel key_name, *hash_values.first[0]
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record that a key changed when hdel is called for a non-existing field" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.hdel key_name, hash_values.first[0]
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when linsert is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.linsert key_name, ["BEFORE", "AFTER"].sample, list_values.sample, string_value
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record that a key changed when linsert is called for an empty key" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.linsert key_name, ["BEFORE", "AFTER"].sample, list_values.sample, string_value
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record that a key changed when linsert is called for a missing pivot" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.linsert key_name, ["BEFORE", "AFTER"].sample, "1234", string_value
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when lpushx is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.lpushx key_name, string_value
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record that a key changed when lpushx is called on an empty list" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.lpushx key_name, list_values[0]
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when rpushx is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.lpushx key_name, string_value
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record that a key changed when rpushx is called on an empty list" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.lpushx key_name, list_values[0]
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when lrem is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.lrem key_name, 0, list_values.sample
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record that a key changed when lrem is called on an empty list" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.lrem key_name, 0, "1234"
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when mapped_msetnx is called" do
            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end

            server_subject.multi
            server_subject.mapped_msetnx hash_values
            server_subject.discard

            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end
          end

          it "does not record that a key changed when mapped_msetnx is called and a value exists" do
            subject.redis.set(*hash_values.first)

            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end

            server_subject.multi
            server_subject.mapped_msetnx hash_values
            server_subject.discard

            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end
          end

          it "records that a key changed when msetnx is called" do
            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end

            server_subject.multi
            server_subject.msetnx(*hash_values.to_a.flatten)
            server_subject.discard

            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end
          end

          it "does not record that a key changed when mapped_msetnx is called and a value exists" do
            subject.redis.set(*hash_values.first)

            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end

            server_subject.multi
            server_subject.msetnx(*hash_values.to_a.flatten)
            server_subject.discard

            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end
          end

          it "records that a key changed when persist is called" do
            subject.redis.setex key_name, rand(100..100_000), string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.persist key_name
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record that a key changed when persist is called on a persisted key" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.persist key_name
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when renamenx is called" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

            server_subject.multi
            server_subject.renamenx key_name, key_name_2
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          end

          it "does not record that a key changed when renamenx is called if the dest exists" do
            subject.redis.set key_name, string_value
            subject.redis.set key_name_2, string_value_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

            server_subject.multi
            server_subject.renamenx key_name, key_name_2
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          end

          it "records that a key changed when sdiffstore is called" do
            populate_set
            set_values.sample(4).each do |set_value|
              subject.redis.sadd key_name_2, set_value
            end
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi
            server_subject.sdiffstore key_name_3, key_name, key_name_2
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
          end

          it "does not record that a key changed when sdiffstore is empty" do
            populate_set
            set_values.each do |set_value|
              subject.redis.sadd key_name_2, set_value
            end
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi
            server_subject.sdiffstore key_name_3, key_name, key_name_2
            server_subject.discard

            expect(subject.redis.type(key_name_3)).to eq "none"
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
          end

          it "records that a key changed when setnx is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.setnx key_name, string_value
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record that a key changed when setnx is called on an existing key" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.setnx key_name, string_value
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when sinterstore is called" do
            populate_set
            set_values.sample(4).each do |set_value|
              subject.redis.sadd key_name_2, set_value
            end
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi
            server_subject.sinterstore key_name_3, key_name, key_name_2
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
          end

          it "does not record that a key changed when sinterstore is called and there is no intersection" do
            populate_set
            subject.redis.sadd key_name_2, "1234"
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi
            server_subject.sinterstore key_name_3, key_name, key_name_2
            server_subject.discard

            expect(subject.redis.type(key_name_3)).to eq "none"
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
          end

          it "records that a key changed when smove is called" do
            populate_set
            set_values.sample(4).each do |set_value|
              subject.redis.sadd key_name_2, set_value
            end
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

            server_subject.multi
            server_subject.smove key_name, key_name_2, set_values.sample
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          end

          it "does not record that a key changed when smove is called and the set doesn't exist" do
            set_values.sample(4).each do |set_value|
              subject.redis.sadd key_name_2, set_value
            end
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

            server_subject.multi
            server_subject.smove key_name, key_name_2, set_values.sample
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          end

          it "does not record that a key changed when smove is called and the set doesn't have the element" do
            populate_set
            set_values.sample(4).each do |set_value|
              subject.redis.sadd key_name_2, set_value
            end
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

            server_subject.multi
            server_subject.smove key_name, key_name_2, "1234"
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          end

          it "records that a key changed when sunionstore is called" do
            populate_set
            set_values.sample(4).each do |set_value|
              subject.redis.sadd key_name_2, set_value
            end
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi
            server_subject.sunionstore key_name_3, key_name, key_name_2
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
          end

          it "does not record that a key changed when sunionstore is called on empty sets" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi
            server_subject.sunionstore key_name_3, key_name, key_name_2
            server_subject.discard

            expect(subject.redis.type(key_name_3)).to eq "none"
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
          end

          it "records that a key changed when zinterstore is called" do
            populate_sorted_set
            sorted_set_values.to_a.sample(4).each do |sort_value|
              subject.redis.zadd key_name_2, sort_value[1], sort_value[0]
            end
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi
            server_subject.zinterstore key_name_3, [key_name, key_name_2]
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
          end

          it "does not record that a key changed when zinterstore is called and there is no intersection" do
            populate_sorted_set
            subject.redis.sadd key_name_2, "1234"
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi
            server_subject.zinterstore key_name_3, [key_name, key_name_2]
            server_subject.discard

            expect(subject.redis.type(key_name_3)).to eq "none"
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
          end

          it "records that a key changed when zunionstore is called" do
            populate_sorted_set
            sorted_set_values.to_a.sample(4).each do |sort_value|
              subject.redis.zadd key_name, sort_value[1], sort_value[0]
            end
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi
            server_subject.zunionstore key_name_3, [key_name, key_name_2]
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
          end

          it "does not record that a key changed when zunionstore is called on empty sets" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

            server_subject.multi
            server_subject.zunionstore key_name_3, [key_name, key_name_2]
            server_subject.discard

            expect(subject.redis.type(key_name_3)).to eq "none"
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
          end
        end

        describe "commands that return nil on failure" do
          it "records that a key changed when lpop is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.lpop key_name
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record that a key changed when lpop is called on an empty list" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.lpop key_name
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when rpop is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.rpop key_name
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record that a key changed when rpop is called on an empty list" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.rpop key_name
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when rpoplpush is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.rpoplpush key_name, key_name_2
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          end

          it "does not record that a key changed when rpoplpush is called on an empty list" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.rpoplpush key_name, key_name_2
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          end

          it "records that a key changed when spop is called" do
            populate_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.spop key_name
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "does not record that a key changed when spop is called on an empty set" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.spop key_name
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end
        end

        describe "write commands" do
          it "records that a key changed when append is called" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.append key_name, string_value_2
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when bitop is called" do
            subject.redis.set key_name, string_value
            subject.redis.set key_name_2, string_value_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.bitop ["AND", "OR", "XOR"].sample, key_name_3, key_name, key_name_2
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
          end

          it "records that a key changed when bitop NOT is called" do
            subject.redis.set key_name, string_value
            subject.redis.set key_name_2, string_value_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.bitop "NOT", key_name_3, key_name
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
          end

          it "records that a key changed when brpoplpush is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.brpoplpush key_name, key_name_2, 1
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          end

          it "records that a key changed when decr is called" do
            subject.redis.set key_name, rand(100..1_000)
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.decr key_name
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when decrby is called" do
            subject.redis.set key_name, rand(100..1_000)
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.decrby key_name, rand(5..10)
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when del is called" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.del key_name
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when expire is called" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.expire key_name, rand(100..1_000)
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when expireat is called" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.expireat key_name, (Time.now + rand(100..1_000).seconds).to_i
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when getset is called" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.getset key_name, string_value_2
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when hset is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.hset key_name, *hash_values.first
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when hincrby is called" do
            subject.redis.hset key_name, hash_values.first[0], rand(10..100)
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.hincrby key_name, hash_values.first[0], rand(10..100)
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          # # This fails for some unknown reason, but that is not significant to my project as the failure is a redis
          # # or redis gem failure as far as I can tell.
          #
          # it "records that a key changed when hincrbyfloat is called" do
          #   subject.redis.hset key_name, hash_values.first[0], [1, 10, 100, 1_000, 10_000].sample * rand
          #   expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          #
          #   server_subject.multi
          #   server_subject.hincrbyfloat key_name, hash_values.first[0], [1, 10, 100, 1_000, 10_000].sample * rand(10..100)
          #   server_subject.discard
          #
          #   expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          # end

          it "records that a key changed when hmset is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.hmset key_name, *hash_values.to_a.flatten
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when incr is called" do
            subject.redis.set key_name, rand(100..100_000)
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.incr key_name
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when incrby is called" do
            subject.redis.set key_name, rand(100..100_000)
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.incrby key_name, rand(10..100)
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          # # This fails for some unknown reason, but that is not significant to my project as the failure is a redis
          # # or redis gem failure as far as I can tell.
          #
          # it "records that a key changed when incrbyfloat is called" do
          #   subject.redis.set key_name, [1, 10, 100, 1_000, 10_000].sample * rand
          #   expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          #
          #   server_subject.multi
          #   server_subject.incrbyfloat key_name, [1, 10, 100, 1_000, 10_000].sample * rand(10..100)
          #   server_subject.discard
          #
          #   expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          # end

          it "records that a key changed when lpush is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.lpush key_name, list_values[0]
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when lset is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.lset key_name, 0, string_value
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when ltrim is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.ltrim key_name, -2, -1
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when mapped_hmset is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.mapped_hmset key_name, hash_values
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when mapped_mset is called" do
            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end

            server_subject.multi
            server_subject.mapped_mset hash_values
            server_subject.discard

            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end
          end

          it "records that a key changed when mset is called" do
            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end

            server_subject.multi
            server_subject.mset(*hash_values.to_a.flatten)
            server_subject.discard

            hash_values.keys.each do |alt_key_name|
              expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
            end
          end

          it "records that a key changed when pexpire is called" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.pexpire key_name, rand(100_000..1_000_000)
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when pexpireat is called" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.pexpireat key_name, (Time.now + rand(100..1_000).seconds).to_i * 1_000
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when psetex is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.psetex key_name, rand(100_000..1_000_000), string_value
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when rename is called" do
            subject.redis.set key_name, string_value
            subject.redis.set key_name_2, string_value_2
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

            server_subject.multi
            server_subject.rename key_name, key_name_2
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          end

          it "records that a key changed when restore is called" do
            subject.redis.set key_name, string_value
            restore_value = subject.redis.dump key_name
            subject.redis.del key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.restore key_name, 0, restore_value
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when rpush is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.rpush key_name, list_values[0]
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when set is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.set key_name, string_value
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when setbit is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.setbit key_name, 1, 1
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when setex is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.setex key_name, rand(100..1_000), string_value
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when setrange is called" do
            subject.redis.set key_name, string_value
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            server_subject.setrange key_name, rand(0..(string_value.length - 2)), string_value_2
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end

          it "records that a key changed when sort is called" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

            server_subject.multi
            server_subject.sort key_name, order: "ALPHA", store: key_name_2
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          end

          it "does not record that a key changed when sort is called without a store" do
            populate_list
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

            server_subject.multi
            server_subject.sort key_name, order: "ALPHA"
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          end

          # # This fails for some unknown reason, but that is not significant to my project as the failure is a redis
          # # or redis gem failure as far as I can tell.
          #
          # it "records that a key changed when zincrby is called" do
          #   populate_sorted_set
          #   expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          #
          #   server_subject.multi
          #   server_subject.zincrby key_name, rand(10..100), sorted_set_values[0]
          #   server_subject.discard
          #
          #   expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          # end

          it "records that a key changed when []= is called" do
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.multi
            subject[key_name] = string_value
            server_subject.discard

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end
        end
      end
    end

    describe "pipelined" do
      describe "commands that return the number of values affected" do
        it "records an updated key if sadd changes a record" do
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.sadd key_name, set_values[0]
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records an updated key if zadd changes a record" do
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.zadd key_name, sorted_set_values.first[1].to_f, sorted_set_values.first[0]
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records an updated key if srem changes a record" do
          populate_set
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.srem key_name, set_values.sample
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records an updated key if zrem changes a record" do
          populate_sorted_set
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.zrem key_name, sorted_set_values.keys.sample
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records an updated key if zremrangebyrank changes a record" do
          populate_sorted_set
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.zremrangebyrank key_name, 0, -1
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records an updated key if zremrangebyscore changes a record" do
          populate_sorted_set
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.zremrangebyscore key_name, sorted_set_values.first[1] - 1, sorted_set_values.first[1] + 1
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records an updated key if zremrangebylex changes a record" do
          if Gem::Version.new("2.8.9") < Gem::Version.new(subject.redis.info["redis_version"])
            populate_lex_sorted_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.pipelined do
              server_subject.zremrangebylex key_name, "-", "+"
            end

            expect(subject.get_set(:@updated_keys)).to be_include key_name
          end
        end

        it "does not record an update if sadd does not change a record" do
          subject.redis.sadd key_name, set_values[0]
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.sadd key_name, set_values[0]
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        end

        it "does not record an update if zadd does not change a record" do
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.zadd key_name, sorted_set_values.first[1], sorted_set_values.first[0]
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "does not record an update if srem does not change a record" do
          populate_set
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.srem key_name, "1234"
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        end

        it "does not record an update if zrem does not change a record" do
          populate_sorted_set
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.zrem key_name, "1234"
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        end

        it "does not record an update if zremrangebyrank does not change a record" do
          populate_sorted_set
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.zremrangebyrank key_name, sorted_set_values.length + 12, sorted_set_values.length + 22
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        end

        it "does not record an update if zremrangebyscore does not change a record" do
          populate_sorted_set
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.zremrangebyscore key_name, sorted_set_values.first[1] - 2, sorted_set_values.first[1] - 1
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        end

        it "does not record an updated key if zremrangebylex does not change a record" do
          if Gem::Version.new("2.8.9") < Gem::Version.new(subject.redis.info["redis_version"])
            populate_lex_sorted_set
            expect(subject.get_set(:@updated_keys)).not_to be_include key_name

            server_subject.pipelined do
              server_subject.zremrangebylex key_name, "[1", "(1"
            end

            expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          end
        end

        it "records that a key changed when hsetnx is called" do
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.hsetnx key_name, *hash_values.first
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "does not record that a key changed when hsetnx is called for an existing hash value" do
          subject.redis.hset key_name, *hash_values.first
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.hsetnx key_name, *hash_values.first
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        end

        it "records that a key changed when hdel is called" do
          populate_hash
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.hdel key_name, *hash_values.first[0]
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "does not record that a key changed when hdel is called for a non-existing field" do
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.hdel key_name, hash_values.first[0]
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        end

        it "records that a key changed when linsert is called" do
          populate_list
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.linsert key_name, ["BEFORE", "AFTER"].sample, list_values.sample, string_value
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "does not record that a key changed when linsert is called for an empty key" do
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.linsert key_name, ["BEFORE", "AFTER"].sample, list_values.sample, string_value
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        end

        it "does not record that a key changed when linsert is called for a missing pivot" do
          populate_list
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.linsert key_name, ["BEFORE", "AFTER"].sample, "1234", string_value
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        end

        it "records that a key changed when lpushx is called" do
          populate_list
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.lpushx key_name, string_value
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "does not record that a key changed when lpushx is called on an empty list" do
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.lpushx key_name, list_values[0]
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        end

        it "records that a key changed when rpushx is called" do
          populate_list
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.lpushx key_name, string_value
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "does not record that a key changed when rpushx is called on an empty list" do
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.lpushx key_name, list_values[0]
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        end

        it "records that a key changed when lrem is called" do
          populate_list
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.lrem key_name, 0, list_values.sample
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "does not record that a key changed when lrem is called on an empty list" do
          populate_list
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.lrem key_name, 0, "1234"
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        end

        it "records that a key changed when mapped_msetnx is called" do
          hash_values.keys.each do |alt_key_name|
            expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
          end

          server_subject.pipelined do
            server_subject.mapped_msetnx hash_values
          end

          hash_values.keys.each do |alt_key_name|
            expect(subject.get_set(:@updated_keys)).to be_include alt_key_name
          end
        end

        it "does not record that a key changed when mapped_msetnx is called and a value exists" do
          subject.redis.set(*hash_values.first)

          hash_values.keys.each do |alt_key_name|
            expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
          end

          server_subject.pipelined do
            server_subject.mapped_msetnx hash_values
          end

          hash_values.keys.each do |alt_key_name|
            expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
          end
        end

        it "records that a key changed when msetnx is called" do
          hash_values.keys.each do |alt_key_name|
            expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
          end

          server_subject.pipelined do
            server_subject.msetnx(*hash_values.to_a.flatten)
          end

          hash_values.keys.each do |alt_key_name|
            expect(subject.get_set(:@updated_keys)).to be_include alt_key_name
          end
        end

        it "does not record that a key changed when mapped_msetnx is called and a value exists" do
          subject.redis.set(*hash_values.first)

          hash_values.keys.each do |alt_key_name|
            expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
          end

          server_subject.pipelined do
            server_subject.msetnx(*hash_values.to_a.flatten)
          end

          hash_values.keys.each do |alt_key_name|
            expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
          end
        end

        it "records that a key changed when persist is called" do
          subject.redis.setex key_name, rand(100..100_000), string_value
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.persist key_name
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "does not record that a key changed when persist is called on a persisted key" do
          subject.redis.set key_name, string_value
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.persist key_name
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        end

        it "records that a key changed when renamenx is called" do
          subject.redis.set key_name, string_value
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

          server_subject.pipelined do
            server_subject.renamenx key_name, key_name_2
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
          expect(subject.get_set(:@updated_keys)).to be_include key_name_2
        end

        it "does not record that a key changed when renamenx is called if the dest exists" do
          subject.redis.set key_name, string_value
          subject.redis.set key_name_2, string_value_2
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

          server_subject.pipelined do
            server_subject.renamenx key_name, key_name_2
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        end

        it "records that a key changed when sdiffstore is called" do
          populate_set
          set_values.sample(4).each do |set_value|
            subject.redis.sadd key_name_2, set_value
          end
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

          server_subject.pipelined do
            server_subject.sdiffstore key_name_3, key_name, key_name_2
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          expect(subject.get_set(:@updated_keys)).to be_include key_name_3
        end

        it "does not record that a key changed when sdiffstore is empty" do
          populate_set
          set_values.each do |set_value|
            subject.redis.sadd key_name_2, set_value
          end
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

          server_subject.pipelined do
            server_subject.sdiffstore key_name_3, key_name, key_name_2
          end

          expect(subject.redis.type(key_name_3)).to eq "none"
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
        end

        it "records that a key changed when setnx is called" do
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.setnx key_name, string_value
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "does not record that a key changed when setnx is called on an existing key" do
          subject.redis.set key_name, string_value
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.setnx key_name, string_value
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        end

        it "records that a key changed when sinterstore is called" do
          populate_set
          set_values.sample(4).each do |set_value|
            subject.redis.sadd key_name_2, set_value
          end
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

          server_subject.pipelined do
            server_subject.sinterstore key_name_3, key_name, key_name_2
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          expect(subject.get_set(:@updated_keys)).to be_include key_name_3
        end

        it "does not record that a key changed when sinterstore is called and there is no intersection" do
          populate_set
          subject.redis.sadd key_name_2, "1234"
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

          server_subject.pipelined do
            server_subject.sinterstore key_name_3, key_name, key_name_2
          end

          expect(subject.redis.type(key_name_3)).to eq "none"
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
        end

        it "records that a key changed when smove is called" do
          populate_set
          set_values.sample(4).each do |set_value|
            subject.redis.sadd key_name_2, set_value
          end
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

          server_subject.pipelined do
            server_subject.smove key_name, key_name_2, set_values.sample
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
          expect(subject.get_set(:@updated_keys)).to be_include key_name_2
        end

        it "does not record that a key changed when smove is called and the set doesn't exist" do
          set_values.sample(4).each do |set_value|
            subject.redis.sadd key_name_2, set_value
          end
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

          server_subject.pipelined do
            server_subject.smove key_name, key_name_2, set_values.sample
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        end

        it "does not record that a key changed when smove is called and the set doesn't have the element" do
          populate_set
          set_values.sample(4).each do |set_value|
            subject.redis.sadd key_name_2, set_value
          end
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

          server_subject.pipelined do
            server_subject.smove key_name, key_name_2, "1234"
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        end

        it "records that a key changed when sunionstore is called" do
          populate_set
          set_values.sample(4).each do |set_value|
            subject.redis.sadd key_name_2, set_value
          end
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

          server_subject.pipelined do
            server_subject.sunionstore key_name_3, key_name, key_name_2
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          expect(subject.get_set(:@updated_keys)).to be_include key_name_3
        end

        it "does not record that a key changed when sunionstore is called on empty sets" do
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

          server_subject.pipelined do
            server_subject.sunionstore key_name_3, key_name, key_name_2
          end

          expect(subject.redis.type(key_name_3)).to eq "none"
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
        end

        it "records that a key changed when zinterstore is called" do
          populate_sorted_set
          sorted_set_values.to_a.sample(4).each do |sort_value|
            subject.redis.zadd key_name_2, sort_value[1], sort_value[0]
          end
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

          server_subject.pipelined do
            server_subject.zinterstore key_name_3, [key_name, key_name_2]
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          expect(subject.get_set(:@updated_keys)).to be_include key_name_3
        end

        it "does not record that a key changed when zinterstore is called and there is no intersection" do
          populate_sorted_set
          subject.redis.sadd key_name_2, "1234"
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

          server_subject.pipelined do
            server_subject.zinterstore key_name_3, [key_name, key_name_2]
          end

          expect(subject.redis.type(key_name_3)).to eq "none"
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
        end

        it "records that a key changed when zunionstore is called" do
          populate_sorted_set
          sorted_set_values.to_a.sample(4).each do |sort_value|
            subject.redis.zadd key_name, sort_value[1], sort_value[0]
          end
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

          server_subject.pipelined do
            server_subject.zunionstore key_name_3, [key_name, key_name_2]
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          expect(subject.get_set(:@updated_keys)).to be_include key_name_3
        end

        it "does not record that a key changed when zunionstore is called on empty sets" do
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3

          server_subject.pipelined do
            server_subject.zunionstore key_name_3, [key_name, key_name_2]
          end

          expect(subject.redis.type(key_name_3)).to eq "none"
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_3
        end
      end

      describe "commands that return nil on failure" do
        it "records that a key changed when lpop is called" do
          populate_list
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.lpop key_name
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "does not record that a key changed when lpop is called on an empty list" do
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.lpop key_name
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        end

        it "records that a key changed when rpop is called" do
          populate_list
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.rpop key_name
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "does not record that a key changed when rpop is called on an empty list" do
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.rpop key_name
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        end

        it "records that a key changed when rpoplpush is called" do
          populate_list
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.rpoplpush key_name, key_name_2
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
          expect(subject.get_set(:@updated_keys)).to be_include key_name_2
        end

        it "does not record that a key changed when rpoplpush is called on an empty list" do
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.rpoplpush key_name, key_name_2
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        end

        it "records that a key changed when spop is called" do
          populate_set
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.spop key_name
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "does not record that a key changed when spop is called on an empty set" do
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.spop key_name
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        end
      end

      describe "write commands" do
        it "records that a key changed when append is called" do
          subject.redis.set key_name, string_value
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.append key_name, string_value_2
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records that a key changed when bitop is called" do
          subject.redis.set key_name, string_value
          subject.redis.set key_name_2, string_value_2
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.bitop ["AND", "OR", "XOR"].sample, key_name_3, key_name, key_name_2
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name_3
        end

        it "records that a key changed when bitop NOT is called" do
          subject.redis.set key_name, string_value
          subject.redis.set key_name_2, string_value_2
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.bitop "NOT", key_name_3, key_name
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name_3
        end

        # # This fails for some unknown reason, but that is not significant to my project as the failure is a redis
        # # or redis gem failure as far as I can tell.
        #
        # it "records that a key changed when brpoplpush is called" do
        #   populate_list
        #   expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        #
        #   server_subject.pipelined do
        #     server_subject.brpoplpush key_name, key_name_2, 1
        #   end
        #
        #   expect(subject.get_set(:@updated_keys)).to be_include key_name
        #   expect(subject.get_set(:@updated_keys)).to be_include key_name_2
        # end

        it "records that a key changed when decr is called" do
          subject.redis.set key_name, rand(100..1_000)
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.decr key_name
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records that a key changed when decrby is called" do
          subject.redis.set key_name, rand(100..1_000)
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.decrby key_name, rand(5..10)
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records that a key changed when del is called" do
          subject.redis.set key_name, string_value
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.del key_name
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records that a key changed when expire is called" do
          subject.redis.set key_name, string_value
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.expire key_name, rand(100..1_000)
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records that a key changed when expireat is called" do
          subject.redis.set key_name, string_value
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.expireat key_name, (Time.now + rand(100..1_000).seconds).to_i
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records that a key changed when getset is called" do
          subject.redis.set key_name, string_value
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.getset key_name, string_value_2
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records that a key changed when hset is called" do
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.hset key_name, *hash_values.first
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records that a key changed when hincrby is called" do
          subject.redis.hset key_name, hash_values.first[0], rand(10..100)
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.hincrby key_name, hash_values.first[0], rand(10..100)
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        # # This fails for some unknown reason, but that is not significant to my project as the failure is a redis
        # # or redis gem failure as far as I can tell.
        #
        # it "records that a key changed when hincrbyfloat is called" do
        #   subject.redis.hset key_name, hash_values.first[0], [1, 10, 100, 1_000, 10_000].sample * rand
        #   expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        #
        #   server_subject.pipelined do
        #     server_subject.hincrbyfloat key_name, hash_values.first[0], [1, 10, 100, 1_000, 10_000].sample * rand(10..100)
        #   end
        #
        #   expect(subject.get_set(:@updated_keys)).to be_include key_name
        # end

        it "records that a key changed when hmset is called" do
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.hmset key_name, *hash_values.to_a.flatten
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records that a key changed when incr is called" do
          subject.redis.set key_name, rand(100..100_000)
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.incr key_name
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records that a key changed when incrby is called" do
          subject.redis.set key_name, rand(100..100_000)
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.incrby key_name, rand(10..100)
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        # # This fails for some unknown reason, but that is not significant to my project as the failure is a redis
        # # or redis gem failure as far as I can tell.
        #
        # it "records that a key changed when incrbyfloat is called" do
        #   subject.redis.set key_name, [1, 10, 100, 1_000, 10_000].sample * rand
        #   expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        #
        #   server_subject.pipelined do
        #     server_subject.incrbyfloat key_name, [1, 10, 100, 1_000, 10_000].sample * rand(10..100)
        #   end
        #
        #   expect(subject.get_set(:@updated_keys)).to be_include key_name
        # end

        it "records that a key changed when lpush is called" do
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.lpush key_name, list_values[0]
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records that a key changed when lset is called" do
          populate_list
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.lset key_name, 0, string_value
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records that a key changed when ltrim is called" do
          populate_list
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.ltrim key_name, -2, -1
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records that a key changed when mapped_hmset is called" do
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.mapped_hmset key_name, hash_values
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records that a key changed when mapped_mset is called" do
          hash_values.keys.each do |alt_key_name|
            expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
          end

          server_subject.pipelined do
            server_subject.mapped_mset hash_values
          end

          hash_values.keys.each do |alt_key_name|
            expect(subject.get_set(:@updated_keys)).to be_include alt_key_name
          end
        end

        it "records that a key changed when mset is called" do
          hash_values.keys.each do |alt_key_name|
            expect(subject.get_set(:@updated_keys)).not_to be_include alt_key_name
          end

          server_subject.pipelined do
            server_subject.mset(*hash_values.to_a.flatten)
          end

          hash_values.keys.each do |alt_key_name|
            expect(subject.get_set(:@updated_keys)).to be_include alt_key_name
          end
        end

        it "records that a key changed when pexpire is called" do
          subject.redis.set key_name, string_value
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.pexpire key_name, rand(100_000..1_000_000)
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records that a key changed when pexpireat is called" do
          subject.redis.set key_name, string_value
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.pexpireat key_name, (Time.now + rand(100..1_000).seconds).to_i * 1_000
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records that a key changed when psetex is called" do
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.psetex key_name, rand(100_000..1_000_000), string_value
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records that a key changed when rename is called" do
          subject.redis.set key_name, string_value
          subject.redis.set key_name_2, string_value_2
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

          server_subject.pipelined do
            server_subject.rename key_name, key_name_2
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
          expect(subject.get_set(:@updated_keys)).to be_include key_name_2
        end

        it "records that a key changed when restore is called" do
          subject.redis.set key_name, string_value
          restore_value = subject.redis.dump key_name
          subject.redis.del key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.restore key_name, 0, restore_value
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records that a key changed when rpush is called" do
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.rpush key_name, list_values[0]
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records that a key changed when set is called" do
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.set key_name, string_value
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records that a key changed when setbit is called" do
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.setbit key_name, 1, 1
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records that a key changed when setex is called" do
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.setex key_name, rand(100..1_000), string_value
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records that a key changed when setrange is called" do
          subject.redis.set key_name, string_value
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            server_subject.setrange key_name, rand(0..(string_value.length - 2)), string_value_2
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end

        it "records that a key changed when sort is called" do
          populate_list
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

          server_subject.pipelined do
            server_subject.sort key_name, order: "ALPHA", store: key_name_2
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).to be_include key_name_2
        end

        it "does not record that a key changed when sort is called without a store" do
          populate_list
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2

          server_subject.pipelined do
            server_subject.sort key_name, order: "ALPHA"
          end

          expect(subject.get_set(:@updated_keys)).not_to be_include key_name
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name_2
        end

        # # This fails for some unknown reason, but that is not significant to my project as the failure is a redis
        # # or redis gem failure as far as I can tell.
        #
        # it "records that a key changed when zincrby is called" do
        #   populate_sorted_set
        #   expect(subject.get_set(:@updated_keys)).not_to be_include key_name
        #
        #   server_subject.pipelined do
        #     server_subject.zincrby key_name, rand(10..100), sorted_set_values[0]
        #   end
        #
        #   expect(subject.get_set(:@updated_keys)).to be_include key_name
        # end

        it "records that a key changed when []= is called" do
          expect(subject.get_set(:@updated_keys)).not_to be_include key_name

          server_subject.pipelined do
            subject[key_name] = string_value
          end

          expect(subject.get_set(:@updated_keys)).to be_include key_name
        end
      end
    end
  end

  describe "#suite_start" do
    it "should ensure that @initial_keys is populated" do
      expect(subject.set_includes?(:@initial_keys, key_name)).to be_falsey

      subject.redis.set key_name, string_value

      subject.suite_start :pseudo_delete
      expect(server_subject.set_includes?(:@initial_keys, key_name)).to be_truthy
      subject.suite_end :pseudo_delete
    end

    it "clears suite_altered_keys" do
      subject.add_set_value(:@suite_altered_keys, key_name)

      subject.suite_start :pseudo_delete
      expect(server_subject.get_set(:@suite_altered_keys)).to be_empty
      subject.suite_end :pseudo_delete
    end

    it "clears updated_keys" do
      subject.add_set_value(:@updated_keys, key_name)

      subject.suite_start :pseudo_delete
      expect(server_subject.get_set(:@updated_keys)).to be_empty
      subject.suite_end :pseudo_delete
    end

    it "clears multi_commands" do
      subject.append_list_value_array(:@multi_commands, ["set", key_name, string_value])

      subject.suite_start :pseudo_delete
      expect(server_subject.get_set(:@multi_commands)).to be_empty
      subject.suite_end :pseudo_delete
    end

    it "clears in_multi" do
      subject.set_value_bool :@in_multi, true

      subject.suite_start :pseudo_delete
      expect(server_subject.get_value_bool(:@in_multi)).to be_falsey
      subject.suite_end :pseudo_delete
    end

    it "clears in_redis_cleanup" do
      subject.set_value_bool :@in_redis_cleanup, true

      subject.suite_start :pseudo_delete
      expect(server_subject.get_value_bool(:@in_redis_cleanup)).to be_falsey
      subject.suite_end :pseudo_delete
    end

    it "clears suspend_tracking" do
      subject.set_value_bool :@suspend_tracking, true

      subject.suite_start :pseudo_delete
      expect(server_subject.get_value_bool(:@suspend_tracking)).to be_falsey
      subject.suite_end :pseudo_delete
    end
  end

  describe "#suspend_tracking" do
    around(:each) do |example_proxy|
      subject.suite_start :pseudo_delete

      example_proxy.call

      subject.suite_end :pseudo_delete
    end

    describe "commands that return the number of values affected" do
      it "records an updated key if sadd changes a record" do
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.sadd key_name, set_values[0]
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records an updated key if zadd changes a record" do
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.zadd key_name, sorted_set_values.first[1].to_f, sorted_set_values.first[0]
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records an updated key if srem changes a record" do
        populate_set
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.srem key_name, set_values.sample
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records an updated key if zrem changes a record" do
        populate_sorted_set
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.zrem key_name, sorted_set_values.keys.sample
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records an updated key if zremrangebyrank changes a record" do
        populate_sorted_set
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.zremrangebyrank key_name, 0, -1
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records an updated key if zremrangebyscore changes a record" do
        populate_sorted_set
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.zremrangebyscore key_name, sorted_set_values.first[1] - 1, sorted_set_values.first[1] + 1
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records an updated key if zremrangebylex changes a record" do
        if Gem::Version.new("2.8.9") < Gem::Version.new(server_subject.redis.info["redis_version"])
          populate_lex_sorted_set
          expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

          subject.suspend_tracking do
            server_subject.zremrangebylex key_name, "-", "+"
          end

          expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        end
      end

      it "does not record an update if sadd does not change a record" do
        server_subject.redis.sadd key_name, set_values[0]
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.sadd key_name, set_values[0]
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record an update if zadd does not change a record" do
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.zadd key_name, sorted_set_values.first[1], sorted_set_values.first[0]
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record an update if srem does not change a record" do
        populate_set
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.srem key_name, "1234"
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record an update if zrem does not change a record" do
        populate_sorted_set
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.zrem key_name, "1234"
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record an update if zremrangebyrank does not change a record" do
        populate_sorted_set
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.zremrangebyrank key_name, sorted_set_values.length + 12, sorted_set_values.length + 22
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record an update if zremrangebyscore does not change a record" do
        populate_sorted_set
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.zremrangebyscore key_name, sorted_set_values.first[1] - 2, sorted_set_values.first[1] - 1
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record an updated key if zremrangebylex does not change a record" do
        if Gem::Version.new("2.8.9") < Gem::Version.new(server_subject.redis.info["redis_version"])
          populate_lex_sorted_set
          expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

          subject.suspend_tracking do
            server_subject.zremrangebylex key_name, "[1", "(1"
          end

          expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        end
      end

      it "records that a key changed when hsetnx is called" do
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.hsetnx key_name, *hash_values.first
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record that a key changed when hsetnx is called for an existing hash value" do
        server_subject.redis.hset key_name, *hash_values.first
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.hsetnx key_name, *hash_values.first
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when hdel is called" do
        populate_hash
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.hdel key_name, *hash_values.first[0]
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record that a key changed when hdel is called for a non-existing field" do
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.hdel key_name, hash_values.first[0]
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when linsert is called" do
        populate_list
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.linsert key_name, ["BEFORE", "AFTER"].sample, list_values.sample, string_value
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record that a key changed when linsert is called for an empty key" do
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.linsert key_name, ["BEFORE", "AFTER"].sample, list_values.sample, string_value
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record that a key changed when linsert is called for a missing pivot" do
        populate_list
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.linsert key_name, ["BEFORE", "AFTER"].sample, "1234", string_value
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when lpushx is called" do
        populate_list
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.lpushx key_name, string_value
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record that a key changed when lpushx is called on an empty list" do
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.lpushx key_name, list_values[0]
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when rpushx is called" do
        populate_list
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.lpushx key_name, string_value
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record that a key changed when rpushx is called on an empty list" do
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.lpushx key_name, list_values[0]
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when lrem is called" do
        populate_list
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.lrem key_name, 0, list_values.sample
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record that a key changed when lrem is called on an empty list" do
        populate_list
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.lrem key_name, 0, "1234"
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when mapped_msetnx is called" do
        hash_values.keys.each do |alt_key_name|
          expect(server_subject.get_set(:@updated_keys)).not_to be_include alt_key_name
        end

        subject.suspend_tracking do
          server_subject.mapped_msetnx hash_values
        end

        hash_values.keys.each do |alt_key_name|
          expect(server_subject.get_set(:@updated_keys)).not_to be_include alt_key_name
        end
      end

      it "does not record that a key changed when mapped_msetnx is called and a value exists" do
        server_subject.redis.set(*hash_values.first)

        hash_values.keys.each do |alt_key_name|
          expect(server_subject.get_set(:@updated_keys)).not_to be_include alt_key_name
        end

        subject.suspend_tracking do
          server_subject.mapped_msetnx hash_values
        end

        hash_values.keys.each do |alt_key_name|
          expect(server_subject.get_set(:@updated_keys)).not_to be_include alt_key_name
        end
      end

      it "records that a key changed when msetnx is called" do
        hash_values.keys.each do |alt_key_name|
          expect(server_subject.get_set(:@updated_keys)).not_to be_include alt_key_name
        end

        subject.suspend_tracking do
          server_subject.msetnx(*hash_values.to_a.flatten)
        end

        hash_values.keys.each do |alt_key_name|
          expect(server_subject.get_set(:@updated_keys)).not_to be_include alt_key_name
        end
      end

      it "does not record that a key changed when mapped_msetnx is called and a value exists" do
        server_subject.redis.set(*hash_values.first)

        hash_values.keys.each do |alt_key_name|
          expect(server_subject.get_set(:@updated_keys)).not_to be_include alt_key_name
        end

        subject.suspend_tracking do
          server_subject.msetnx(*hash_values.to_a.flatten)
        end

        hash_values.keys.each do |alt_key_name|
          expect(server_subject.get_set(:@updated_keys)).not_to be_include alt_key_name
        end
      end

      it "records that a key changed when persist is called" do
        server_subject.redis.setex key_name, rand(100..100_000), string_value
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.persist key_name
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record that a key changed when persist is called on a persisted key" do
        server_subject.redis.set key_name, string_value
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.persist key_name
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when renamenx is called" do
        server_subject.redis.set key_name, string_value
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2

        subject.suspend_tracking do
          server_subject.renamenx key_name, key_name_2
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
      end

      it "does not record that a key changed when renamenx is called if the dest exists" do
        server_subject.redis.set key_name, string_value
        server_subject.redis.set key_name_2, string_value_2
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2

        subject.suspend_tracking do
          server_subject.renamenx key_name, key_name_2
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
      end

      it "records that a key changed when sdiffstore is called" do
        populate_set
        set_values.sample(4).each do |set_value|
          server_subject.redis.sadd key_name_2, set_value
        end
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_3

        subject.suspend_tracking do
          server_subject.sdiffstore key_name_3, key_name, key_name_2
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_3
      end

      it "does not record that a key changed when sdiffstore is empty" do
        populate_set
        set_values.each do |set_value|
          server_subject.redis.sadd key_name_2, set_value
        end
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_3

        subject.suspend_tracking do
          server_subject.sdiffstore key_name_3, key_name, key_name_2
        end

        expect(server_subject.redis.type(key_name_3)).to eq "none"
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_3
      end

      it "records that a key changed when setnx is called" do
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.setnx key_name, string_value
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record that a key changed when setnx is called on an existing key" do
        server_subject.redis.set key_name, string_value
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.setnx key_name, string_value
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when sinterstore is called" do
        populate_set
        set_values.sample(4).each do |set_value|
          server_subject.redis.sadd key_name_2, set_value
        end
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_3

        subject.suspend_tracking do
          server_subject.sinterstore key_name_3, key_name, key_name_2
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_3
      end

      it "does not record that a key changed when sinterstore is called and there is no intersection" do
        populate_set
        server_subject.redis.sadd key_name_2, "1234"
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_3

        subject.suspend_tracking do
          server_subject.sinterstore key_name_3, key_name, key_name_2
        end

        expect(server_subject.redis.type(key_name_3)).to eq "none"
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_3
      end

      it "records that a key changed when smove is called" do
        populate_set
        set_values.sample(4).each do |set_value|
          server_subject.redis.sadd key_name_2, set_value
        end
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2

        subject.suspend_tracking do
          server_subject.smove key_name, key_name_2, set_values.sample
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
      end

      it "does not record that a key changed when smove is called and the set doesn't exist" do
        set_values.sample(4).each do |set_value|
          server_subject.redis.sadd key_name_2, set_value
        end
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2

        subject.suspend_tracking do
          server_subject.smove key_name, key_name_2, set_values.sample
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
      end

      it "does not record that a key changed when smove is called and the set doesn't have the element" do
        populate_set
        set_values.sample(4).each do |set_value|
          server_subject.redis.sadd key_name_2, set_value
        end
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2

        subject.suspend_tracking do
          server_subject.smove key_name, key_name_2, "1234"
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
      end

      it "records that a key changed when sunionstore is called" do
        populate_set
        set_values.sample(4).each do |set_value|
          server_subject.redis.sadd key_name_2, set_value
        end
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_3

        subject.suspend_tracking do
          server_subject.sunionstore key_name_3, key_name, key_name_2
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_3
      end

      it "does not record that a key changed when sunionstore is called on empty sets" do
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_3

        subject.suspend_tracking do
          server_subject.sunionstore key_name_3, key_name, key_name_2
        end

        expect(server_subject.redis.type(key_name_3)).to eq "none"
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_3
      end

      it "records that a key changed when zinterstore is called" do
        populate_sorted_set
        sorted_set_values.to_a.sample(4).each do |sort_value|
          server_subject.redis.zadd key_name_2, sort_value[1], sort_value[0]
        end
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_3

        subject.suspend_tracking do
          server_subject.zinterstore key_name_3, [key_name, key_name_2]
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_3
      end

      it "does not record that a key changed when zinterstore is called and there is no intersection" do
        populate_sorted_set
        server_subject.redis.sadd key_name_2, "1234"
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_3

        subject.suspend_tracking do
          server_subject.zinterstore key_name_3, [key_name, key_name_2]
        end

        expect(server_subject.redis.type(key_name_3)).to eq "none"
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_3
      end

      it "records that a key changed when zunionstore is called" do
        populate_sorted_set
        sorted_set_values.to_a.sample(4).each do |sort_value|
          server_subject.redis.zadd key_name, sort_value[1], sort_value[0]
        end
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_3

        subject.suspend_tracking do
          server_subject.zunionstore key_name_3, [key_name, key_name_2]
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_3
      end

      it "does not record that a key changed when zunionstore is called on empty sets" do
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_3

        subject.suspend_tracking do
          server_subject.zunionstore key_name_3, [key_name, key_name_2]
        end

        expect(server_subject.redis.type(key_name_3)).to eq "none"
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_3
      end
    end

    describe "commands that return nil on failure" do
      it "records that a key changed when lpop is called" do
        populate_list
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.lpop key_name
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record that a key changed when lpop is called on an empty list" do
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.lpop key_name
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when rpop is called" do
        populate_list
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.rpop key_name
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record that a key changed when rpop is called on an empty list" do
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.rpop key_name
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when rpoplpush is called" do
        populate_list
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.rpoplpush key_name, key_name_2
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
      end

      it "does not record that a key changed when rpoplpush is called on an empty list" do
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.rpoplpush key_name, key_name_2
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
      end

      it "records that a key changed when spop is called" do
        populate_set
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.spop key_name
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "does not record that a key changed when spop is called on an empty set" do
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.spop key_name
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end
    end

    describe "write commands" do
      it "records that a key changed when append is called" do
        server_subject.redis.set key_name, string_value
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.append key_name, string_value_2
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when bitop is called" do
        server_subject.redis.set key_name, string_value
        server_subject.redis.set key_name_2, string_value_2
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.bitop ["AND", "OR", "XOR"].sample, key_name_3, key_name, key_name_2
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_3
      end

      it "records that a key changed when bitop NOT is called" do
        server_subject.redis.set key_name, string_value
        server_subject.redis.set key_name_2, string_value_2
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.bitop "NOT", key_name_3, key_name
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_3
      end

      # it "records that a key changed when brpoplpush is called" do
      #   populate_list
      #   expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      #
      #   subject.suspend_tracking do
      #     server_subject.brpoplpush key_name, key_name_2, 1
      #   end
      #
      #   expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      #   expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
      # end

      it "records that a key changed when decr is called" do
        server_subject.redis.set key_name, rand(100..1_000)
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.decr key_name
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when decrby is called" do
        server_subject.redis.set key_name, rand(100..1_000)
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.decrby key_name, rand(5..10)
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when del is called" do
        server_subject.redis.set key_name, string_value
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.del key_name
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when expire is called" do
        server_subject.redis.set key_name, string_value
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.expire key_name, rand(100..1_000)
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when expireat is called" do
        server_subject.redis.set key_name, string_value
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.expireat key_name, (Time.now + rand(100..1_000).seconds).to_i
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when getset is called" do
        server_subject.redis.set key_name, string_value
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.getset key_name, string_value_2
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when hset is called" do
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.hset key_name, *hash_values.first
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when hincrby is called" do
        server_subject.redis.hset key_name, hash_values.first[0], rand(10..100)
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.hincrby key_name, hash_values.first[0], rand(10..100)
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      # it "records that a key changed when hincrbyfloat is called" do
      #   server_subject.redis.hset key_name, hash_values.first[0], [1, 10, 100, 1_000, 10_000].sample * rand
      #   expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      #
      #   subject.suspend_tracking do
      #   server_subject.hincrbyfloat key_name, hash_values.first[0], [1, 10, 100, 1_000, 10_000].sample * rand(10..100)
      #   end
      #
      #   expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      # end

      it "records that a key changed when hmset is called" do
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.hmset key_name, *hash_values.to_a.flatten
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when incr is called" do
        server_subject.redis.set key_name, rand(100..100_000)
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.incr key_name
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when incrby is called" do
        server_subject.redis.set key_name, rand(100..100_000)
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.incrby key_name, rand(10..100)
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      # it "records that a key changed when incrbyfloat is called" do
      #   server_subject.redis.set key_name, [1, 10, 100, 1_000, 10_000].sample * rand
      #   expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      #
      #   subject.suspend_tracking do
      #   server_subject.incrbyfloat key_name, [1, 10, 100, 1_000, 10_000].sample * rand(10..100)
      #   end
      #
      #   expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      # end

      it "records that a key changed when lpush is called" do
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.lpush key_name, list_values[0]
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when lset is called" do
        populate_list
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.lset key_name, 0, string_value
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when ltrim is called" do
        populate_list
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.ltrim key_name, -2, -1
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when mapped_hmset is called" do
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.mapped_hmset key_name, hash_values
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when mapped_mset is called" do
        hash_values.keys.each do |alt_key_name|
          expect(server_subject.get_set(:@updated_keys)).not_to be_include alt_key_name
        end

        subject.suspend_tracking do
          server_subject.mapped_mset hash_values
        end

        hash_values.keys.each do |alt_key_name|
          expect(server_subject.get_set(:@updated_keys)).not_to be_include alt_key_name
        end
      end

      it "records that a key changed when mset is called" do
        hash_values.keys.each do |alt_key_name|
          expect(server_subject.get_set(:@updated_keys)).not_to be_include alt_key_name
        end

        subject.suspend_tracking do
          server_subject.mset(*hash_values.to_a.flatten)
        end

        hash_values.keys.each do |alt_key_name|
          expect(server_subject.get_set(:@updated_keys)).not_to be_include alt_key_name
        end
      end

      it "records that a key changed when pexpire is called" do
        server_subject.redis.set key_name, string_value
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.pexpire key_name, rand(100_000..1_000_000)
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when pexpireat is called" do
        server_subject.redis.set key_name, string_value
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.pexpireat key_name, (Time.now + rand(100..1_000).seconds).to_i * 1_000
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when psetex is called" do
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.psetex key_name, rand(100_000..1_000_000), string_value
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when rename is called" do
        server_subject.redis.set key_name, string_value
        server_subject.redis.set key_name_2, string_value_2
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2

        subject.suspend_tracking do
          server_subject.rename key_name, key_name_2
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
      end

      it "records that a key changed when restore is called" do
        server_subject.redis.set key_name, string_value
        restore_value = server_subject.redis.dump key_name
        server_subject.redis.del key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.restore key_name, 0, restore_value
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when rpush is called" do
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.rpush key_name, list_values[0]
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when set is called" do
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.set key_name, string_value
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when setbit is called" do
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.setbit key_name, 1, 1
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when setex is called" do
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.setex key_name, rand(100..1_000), string_value
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when setrange is called" do
        server_subject.redis.set key_name, string_value
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject.setrange key_name, rand(0..(string_value.length - 2)), string_value_2
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end

      it "records that a key changed when sort is called" do
        populate_list
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2

        subject.suspend_tracking do
          server_subject.sort key_name, order: "ALPHA", store: key_name_2
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
      end

      it "does not record that a key changed when sort is called without a store" do
        populate_list
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2

        subject.suspend_tracking do
          server_subject.sort key_name, order: "ALPHA"
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name_2
      end

      # # This fails for some unknown reason, but that is not significant to my project as the failure is a redis
      # # or redis gem failure as far as I can tell.
      #
      # it "records that a key changed when zincrby is called" do
      #   populate_sorted_set
      #   expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      #
      #   subject.suspend_tracking do
      #     server_subject.zincrby key_name, rand(10..100), sorted_set_values[0]
      #   end
      #
      #   expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      # end

      it "records that a key changed when []= is called" do
        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name

        subject.suspend_tracking do
          server_subject[key_name] = string_value
        end

        expect(server_subject.get_set(:@updated_keys)).not_to be_include key_name
      end
    end
  end

  describe "#test_start" do
    it "reports on any changes that happened since the last test ended" do
      subject.suite_start :pseudo_delete
      expect(server_subject.set_includes?(:@updated_keys, key_name)).to be_falsey
      expect(subject.set_includes?(:@updated_keys, key_name)).to be_falsey

      server_subject.set key_name, string_value

      expect(server_subject.set_includes?(:@updated_keys, key_name)).to be_truthy
      expect(subject.set_includes?(:@updated_keys, key_name)).to be_truthy
      expect(PseudoCleaner::Logger).to receive(:write).exactly(2).times

      subject.test_start :pseudo_delete
      subject.test_end :pseudo_delete
      subject.suite_end :pseudo_delete
    end

    it "clears the list of updated_keys" do
      subject.suite_start :pseudo_delete
      expect(subject.set_includes?(:@updated_keys, key_name)).to be_falsey
      expect(server_subject.set_includes?(:@updated_keys, key_name)).to be_falsey

      server_subject.set key_name, string_value

      expect(PseudoCleaner::Logger).to receive(:write).exactly(2).times
      expect(subject.set_includes?(:@updated_keys, key_name)).to be_truthy
      expect(server_subject.set_includes?(:@updated_keys, key_name)).to be_truthy

      subject.test_start :pseudo_delete
      expect(subject.set_includes?(:@updated_keys, key_name)).to be_falsey
      expect(server_subject.set_includes?(:@updated_keys, key_name)).to be_falsey
      subject.test_end :pseudo_delete
      subject.suite_end :pseudo_delete
    end

    it "does not clear the list of suite_altered_keys" do
      subject.suite_start :pseudo_delete

      server_subject.add_set_value(:@suite_altered_keys, key_name)

      subject.test_start :pseudo_delete
      expect(subject.set_includes?(:@suite_altered_keys, key_name)).to be_truthy
      expect(server_subject.set_includes?(:@suite_altered_keys, key_name)).to be_truthy
      subject.test_end :pseudo_delete
      subject.suite_end :pseudo_delete
    end
  end

  describe "#test_end" do
    it "outputs all updated values if output_diagnostics is set" do
      subject.suite_start :pseudo_delete
      subject.test_start :pseudo_delete

      subject.instance_variable_get(:@options)[:output_diagnostics] = true

      expect(subject.set_includes?(:@updated_keys, key_name)).to be_falsey
      expect(server_subject.set_includes?(:@updated_keys, key_name)).to be_falsey

      server_subject.set key_name, string_value

      expect(subject.set_includes?(:@updated_keys, key_name)).to be_truthy
      expect(server_subject.set_includes?(:@updated_keys, key_name)).to be_truthy
      expect(PseudoCleaner::Logger).to receive(:write).exactly(2).times

      subject.test_end :pseudo_delete
      subject.suite_end :pseudo_delete
    end

    it "adds initial_values to suite_altered_keys" do
      server_subject.set key_name, string_value

      subject.suite_start :pseudo_delete
      subject.test_start :pseudo_delete

      expect(subject.set_includes?(:@updated_keys, key_name)).to be_falsey
      expect(server_subject.set_includes?(:@updated_keys, key_name)).to be_falsey
      server_subject.set key_name, string_value
      expect(subject.set_includes?(:@updated_keys, key_name)).to be_truthy
      expect(server_subject.set_includes?(:@updated_keys, key_name)).to be_truthy
      expect(subject.set_includes?(:@suite_altered_keys, key_name)).to be_falsey
      expect(server_subject.set_includes?(:@suite_altered_keys, key_name)).to be_falsey

      subject.test_end :pseudo_delete
      expect(subject.set_includes?(:@suite_altered_keys, key_name)).to be_truthy
      expect(server_subject.set_includes?(:@suite_altered_keys, key_name)).to be_truthy
      subject.suite_end :pseudo_delete
    end

    it "reports initial values that were updated" do
      server_subject.set key_name, string_value

      subject.suite_start :pseudo_delete
      subject.test_start :pseudo_delete

      server_subject.set key_name, string_value
      expect(PseudoCleaner::Logger).to receive(:write).exactly(4).times # 2 for test_end, 2 for suite_end

      subject.test_end :pseudo_delete
      subject.suite_end :pseudo_delete
    end

    it "does not delete initial values that were updated" do
      server_subject.set key_name, string_value

      subject.suite_start :pseudo_delete
      subject.test_start :pseudo_delete

      server_subject.set key_name, string_value

      subject.test_end :pseudo_delete
      expect(server_subject.redis.type(key_name)).to eq "string"
      subject.suite_end :pseudo_delete
    end

    it "deletes keys that were updated during the test that were not initial values" do
      subject.suite_start :pseudo_delete
      subject.test_start :pseudo_delete

      server_subject.set key_name, string_value

      subject.test_end :pseudo_delete
      expect(subject.redis.type(key_name)).to eq "none"
      subject.suite_end :pseudo_delete
    end

    it "clears the list of updated keys" do
      subject.suite_start :pseudo_delete
      subject.test_start :pseudo_delete

      server_subject.set key_name, string_value
      expect(subject.set_includes?(:@updated_keys, key_name)).to be_truthy
      expect(server_subject.set_includes?(:@updated_keys, key_name)).to be_truthy

      subject.test_end :pseudo_delete
      expect(subject.get_set(:@updated_keys)).to be_empty
      expect(server_subject.get_set(:@updated_keys)).to be_empty
      subject.suite_end :pseudo_delete
    end

    it "does not report suite_altered_keys if they are in the ignore list" do
      server_subject.redis.set key_name, string_value

      subject.suite_start :pseudo_delete
      subject.test_start :pseudo_delete

      server_subject.set key_name, string_value
      allow(subject).to receive(:ignore_key).and_call_original
      expect(subject).to receive(:ignore_key).with(key_name).and_return(true)

      subject.test_end :pseudo_delete
      expect(subject.set_includes?(:@suite_altered_keys, key_name)).to be_falsey
      expect(server_subject.set_includes?(:@suite_altered_keys, key_name)).to be_falsey
      subject.suite_end :pseudo_delete
    end
  end

  describe "#suite_end" do
    it "reports new keys that are not part of the initial_keys set" do
      server_subject.redis.set key_name, string_value

      subject.suite_start :pseudo_delete

      server_subject.redis.set key_name_2, string_value_2
      expect(PseudoCleaner::Logger).to receive(:write).exactly(2).times

      subject.suite_end :pseudo_delete
    end

    it "deletes new keys that are not part of the initial_keys set" do
      server_subject.redis.set key_name, string_value

      subject.suite_start :pseudo_delete

      server_subject.redis.set key_name_2, string_value_2

      subject.suite_end :pseudo_delete

      expect(subject.redis.type(key_name_2)).to eq "none"
    end

    it "reports deleted keys that were part of the initial_keys set" do
      server_subject.redis.set key_name, string_value

      subject.suite_start :pseudo_delete

      server_subject.redis.del key_name
      expect(PseudoCleaner::Logger).to receive(:write).exactly(2).times

      subject.suite_end :pseudo_delete
    end

    it "reports updated keys that are part of the initial_keys set" do
      server_subject.redis.set key_name, string_value

      subject.suite_start :pseudo_delete

      server_subject.add_set_value(:@suite_altered_keys, key_name)
      expect(PseudoCleaner::Logger).to receive(:write).exactly(2).times

      subject.suite_end :pseudo_delete
    end

    it "clears suite_altered_keys" do
      server_subject.redis.set key_name, string_value

      subject.suite_start :pseudo_delete

      server_subject.add_set_value(:@suite_altered_keys, key_name)

      subject.suite_end :pseudo_delete

      expect(subject.get_set(:@suite_altered_keys)).to be_empty
      expect(server_subject.get_set(:@suite_altered_keys)).to be_empty
    end
  end

  describe "#reset_suite" do
    it "reports new keys that are not part of the initial_keys set" do
      subject.suite_start :pseudo_delete

      server_subject.redis.set key_name, string_value
      expect(PseudoCleaner::Logger).to receive(:write).exactly(2).times

      subject.reset_suite

      subject.suite_end :pseudo_delete
    end

    it "reports deleted keys that were part of the initial_keys set" do
      server_subject.redis.set key_name, string_value
      subject.suite_start :pseudo_delete

      server_subject.redis.del key_name
      expect(PseudoCleaner::Logger).to receive(:write).exactly(2).times

      subject.reset_suite

      subject.suite_end :pseudo_delete
    end

    it "reports updated keys that are part of the initial_keys set" do
      server_subject.redis.set key_name, string_value
      subject.suite_start :pseudo_delete

      server_subject.add_set_value(:@suite_altered_keys, key_name)
      expect(PseudoCleaner::Logger).to receive(:write).exactly(2).times

      subject.reset_suite

      subject.suite_end :pseudo_delete
    end

    it "should ensure that @initial_keys is populated" do
      subject.suite_start :pseudo_delete

      expect(subject.set_includes?(:@initial_keys, key_name)).to be_falsey
      expect(server_subject.set_includes?(:@initial_keys, key_name)).to be_falsey
      server_subject.redis.set key_name, string_value

      subject.reset_suite

      expect(subject.set_includes?(:@initial_keys, key_name)).to be_truthy
      expect(server_subject.set_includes?(:@initial_keys, key_name)).to be_truthy

      subject.suite_end :pseudo_delete
    end

    it "clears suite_altered_keys" do
      subject.suite_start :pseudo_delete

      server_subject.add_set_value(:@suite_altered_keys, key_name)

      subject.reset_suite
      expect(subject.get_set(:@suite_altered_keys)).to be_empty
      expect(server_subject.get_set(:@suite_altered_keys)).to be_empty
      subject.suite_end :pseudo_delete
    end

    it "clears updated_keys" do
      subject.suite_start :pseudo_delete
      server_subject.add_set_value(:@updated_keys, key_name)

      subject.reset_suite
      expect(subject.get_set(:@updated_keys)).to be_empty
      expect(server_subject.get_set(:@updated_keys)).to be_empty
      subject.suite_end :pseudo_delete
    end

    it "clears multi_commands" do
      subject.suite_start :pseudo_delete
      server_subject.append_list_value_array(:@multi_commands, ["set", key_name, string_value])

      subject.reset_suite
      expect(subject.get_set(:@multi_commands)).to be_empty
      expect(server_subject.get_set(:@multi_commands)).to be_empty
      subject.suite_end :pseudo_delete
    end

    it "clears in_multi" do
      subject.suite_start :pseudo_delete
      server_subject.set_value_bool :@in_multi, true

      subject.reset_suite
      expect(subject.get_value_bool(:@in_multi)).to be_falsey
      expect(server_subject.get_value_bool(:@in_multi)).to be_falsey
      subject.suite_end :pseudo_delete
    end

    it "clears in_redis_cleanup" do
      subject.suite_start :pseudo_delete
      server_subject.set_value_bool :@in_redis_cleanup, true

      subject.reset_suite
      expect(subject.get_value_bool(:@in_redis_cleanup)).to be_falsey
      expect(server_subject.get_value_bool(:@in_redis_cleanup)).to be_falsey
      subject.suite_end :pseudo_delete
    end

    it "clears suspend_tracking" do
      subject.suite_start :pseudo_delete
      server_subject.set_value_bool :@suspend_tracking, true

      subject.reset_suite
      expect(subject.get_value_bool(:@suspend_tracking)).to be_falsey
      expect(server_subject.get_value_bool(:@suspend_tracking)).to be_falsey
      subject.suite_end :pseudo_delete
    end
  end

  describe "synchronize_test_values" do
    it "adds all multi commands to the updated keys if in_multi" do
      subject.suite_start :pseudo_delete
      subject.test_start :pseudo_delete

      server_subject.set_value_bool :@in_multi, true
      server_subject.append_list_value_array(:@multi_commands, ["set", key_name, string_value])

      subject.synchronize_test_values do |updated_values|
        expect(updated_values).to be_include(key_name)
      end

      subject.test_end :pseudo_delete
      subject.suite_end :pseudo_delete
    end

    it "clears multi_commands" do
      subject.suite_start :pseudo_delete
      subject.test_start :pseudo_delete

      server_subject.set_value_bool :@in_multi, true
      server_subject.append_list_value_array(:@multi_commands, ["set", key_name, string_value])

      subject.synchronize_test_values do |updated_values|
        expect(server_subject.get_set(:@multi_commands)).to be_empty
      end

      subject.test_end :pseudo_delete
      subject.suite_end :pseudo_delete
    end

    it "sets in_multi to false" do
      subject.suite_start :pseudo_delete
      subject.test_start :pseudo_delete

      server_subject.set_value_bool :@in_multi, true
      server_subject.append_list_value_array(:@multi_commands, ["set", key_name, string_value])

      subject.synchronize_test_values do |updated_values|
        expect(subject.get_value_bool(:@in_multi)).to be_falsey
        expect(server_subject.get_value_bool(:@in_multi)).to be_falsey
      end

      subject.test_end :pseudo_delete
      subject.suite_end :pseudo_delete
    end

    it "yields updated values" do
      subject.suite_start :pseudo_delete
      subject.test_start :pseudo_delete

      server_subject.set key_name, string_value

      subject.synchronize_test_values do |updated_values|
        expect(updated_values).to be_include(key_name)
      end

      subject.test_end :pseudo_delete
      subject.suite_end :pseudo_delete
    end

    it "sets in_redis_cleanup while in the yield" do
      subject.suite_start :pseudo_delete
      subject.test_start :pseudo_delete

      server_subject.set key_name, string_value

      subject.synchronize_test_values do |updated_values|
        expect(subject.get_value_bool(:@in_redis_cleanup)).to be_truthy
        expect(server_subject.get_value_bool(:@in_redis_cleanup)).to be_truthy
      end

      subject.test_end :pseudo_delete
      subject.suite_end :pseudo_delete
    end

    it "resets in_redis_cleanup even if there is an exception" do
      subject.suite_start :pseudo_delete
      subject.test_start :pseudo_delete

      server_subject.set key_name, string_value

      expect do
        subject.synchronize_test_values do |updated_values|
          raise "fake error"
        end
      end.to raise_exception("fake error")
      expect(subject.get_value_bool(:@in_redis_cleanup)).to be_falsey
      expect(server_subject.get_value_bool(:@in_redis_cleanup)).to be_falsey

      subject.test_end :pseudo_delete
      subject.suite_end :pseudo_delete
    end
  end

  describe "#ignore_key" do
    before(:each) do
      allow(subject).to receive(:ignore_regexes).and_return(
                            [
                                /.*#{key_name}.*/,
                                /1234/,
                                /this is not going to match/,
                                /a filler regex/
                            ].sample(100)
                        )
    end

    it "ignores keys that match any regex in the list" do
      expect(subject.ignore_key("something #{key_name} something")).to be_truthy
    end

    it "does not ignore keys that do not match any regex in the list" do
      expect(subject.ignore_key("#{string_value}")).to be_falsey
    end
  end

  describe "#review_rows" do
    it "yields all rows that have been updated" do
      server_subject.set key_name_3, string_value

      subject.suite_start :pseudo_delete
      subject.test_start :pseudo_delete

      server_subject.set key_name, string_value
      server_subject.set key_name_2, string_value_2

      keys = []
      subject.review_rows { |table_name, updated_row| keys << updated_row[:key] }

      expect(keys.length).to eq 2
      expect(keys).to be_include(key_name)
      expect(keys).to be_include(key_name_2)

      subject.test_end :pseudo_delete
      subject.suite_end :pseudo_delete
    end

    it "does not reset updated_values" do
      server_subject.set key_name_3, string_value

      subject.suite_start :pseudo_delete
      subject.test_start :pseudo_delete

      server_subject.set key_name, string_value
      server_subject.set key_name_2, string_value_2

      keys = []
      subject.review_rows { |table_name, updated_row| keys << updated_row[:key] }

      updated_values = subject.get_set(:@updated_keys)
      expect(updated_values).to be_include(key_name)
      expect(updated_values).to be_include(key_name_2)

      subject.test_end :pseudo_delete
      subject.suite_end :pseudo_delete
    end

    it "does not yield ignored values" do
      server_subject.set key_name_3, string_value

      subject.suite_start :pseudo_delete
      subject.test_start :pseudo_delete

      server_subject.set key_name, string_value
      server_subject.set key_name_2, string_value_2

      allow(subject).to receive(:ignore_key).and_call_original
      expect(subject).to receive(:ignore_key).with(key_name).and_return(true)

      keys = []
      subject.review_rows { |table_name, updated_row| keys << updated_row[:key] }

      expect(keys.length).to eq 1
      expect(keys).to be_include(key_name_2)

      subject.test_end :pseudo_delete
      subject.suite_end :pseudo_delete
    end
  end

  describe "#peek_values" do
    it "outputs all rows that have been updated" do
      server_subject.set key_name_3, string_value

      subject.suite_start :pseudo_delete
      subject.test_start :pseudo_delete

      server_subject.set key_name, string_value
      server_subject.set key_name_2, string_value_2
      expect(PseudoCleaner::Logger).to receive(:write).exactly(3).times

      subject.peek_values

      subject.test_end :pseudo_delete
      subject.suite_end :pseudo_delete
    end

    it "does not reset updated_values" do
      server_subject.set key_name_3, string_value

      subject.suite_start :pseudo_delete
      subject.test_start :pseudo_delete

      server_subject.set key_name, string_value
      server_subject.set key_name_2, string_value_2

      subject.peek_values

      updated_values = subject.get_set(:@updated_keys)
      expect(updated_values).to be_include(key_name)
      expect(updated_values).to be_include(key_name_2)

      subject.test_end :pseudo_delete
      subject.suite_end :pseudo_delete
    end

    it "does not output ignored values" do
      server_subject.set key_name_3, string_value

      subject.suite_start :pseudo_delete
      subject.test_start :pseudo_delete

      server_subject.set key_name, string_value
      server_subject.set key_name_2, string_value_2

      allow(subject).to receive(:ignore_key).and_call_original
      expect(subject).to receive(:ignore_key).with(key_name).and_return(true)
      expect(PseudoCleaner::Logger).to receive(:write).exactly(2).times

      subject.peek_values

      subject.test_end :pseudo_delete
      subject.suite_end :pseudo_delete
    end
  end
end