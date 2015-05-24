# require "rails_helper"
# require "pseudo_cleaner/redis_cleaner"
#
# RSpec.describe PseudoCleaner::RedisMonitorCleaner, type: :helper do
#   let(:connection_information) { YAML.load(File.read(File.join(File.dirname(__FILE__), "fixtures/resque.yml")))["test"] }
#   let(:redis) { Redis.new(connection_information) }
#   let(:db2_redis) { Redis.new(connection_information.merge({ "db" => 1 })) }
#   let(:ns_redis) { Redis::Namespace.new :name_space_test, redis: redis }
#   let(:set_key) { "\\\"#{Faker::Lorem.sentence}\"\\" }
#   let(:set_value) { "\"#{Faker::Lorem.sentence}\"" }
#   let(:set_key_1) { "\\\"#{Faker::Lorem.sentence}\"\\" }
#   let(:set_value_1) { "\"#{Faker::Lorem.sentence}\"" }
#
#   before(:each) do
#     @before_keys = redis.keys.select { |key| (key =~ /redis_cleaner::synchronization_(?:end_)?key_[0-9]+_[0-9]+/).nil? }
#   end
#
#   after(:each) do
#     redis.del(set_key)
#     db2_redis.del(set_key)
#     redis.del(set_key_1)
#     db2_redis.del(set_key_1)
#
#     end_keys = redis.keys.select { |key| (key =~ /redis_cleaner::synchronization_(?:end_)?key_[0-9]+_[0-9]+/).nil? }
#     expect(end_keys).to eq(@before_keys)
#
#     Redis.current = nil
#   end
#
#   it "cleans up new values at test_end" do
#     cleaner = PseudoCleaner::RedisMonitorCleaner.new(:suite_start, :suite_end, redis, {})
#     cleaner.suite_start :pseudo_delete
#
#     cleaner.test_start :pseudo_delete
#
#     redis.set(set_key, set_value)
#     db2_redis.set(set_key_1, set_value_1)
#
#     cleaner.test_end :pseudo_delete
#
#     expect(redis.get(set_key)).not_to be
#     expect(db2_redis.get(set_key_1)).to eq set_value_1
#
#     cleaner.suite_end :pseudo_delete
#   end
#
#   it "warns of values changed between tests" do
#     cleaner = PseudoCleaner::RedisMonitorCleaner.new(:suite_start, :suite_end, redis, {})
#     cleaner.suite_start :pseudo_delete
#
#     redis.set(set_key, set_value)
#     db2_redis.set(set_key_1, set_value_1)
#
#     expect(PseudoCleaner::Logger).to receive(:write).exactly(2).times.and_call_original
#
#     cleaner.test_start :pseudo_delete
#
#     expect(redis.get(set_key)).not_to be
#     expect(db2_redis.get(set_key_1)).to eq set_value_1
#
#     cleaner.test_end :pseudo_delete
#     cleaner.suite_end :pseudo_delete
#   end
#
#   it "does not warn of existing values not changed during test" do
#     cleaner = PseudoCleaner::RedisMonitorCleaner.new(:suite_start, :suite_end, redis, {})
#
#     redis.set(set_key_1, set_value)
#
#     cleaner.suite_start :pseudo_delete
#     cleaner.test_start :pseudo_delete
#
#     redis.get(set_key_1)
#     redis.set(set_key, set_value)
#     db2_redis.set(set_key_1, set_value_1)
#
#     expect(Object).not_to receive(:const_defined?).with("Cornucopia", false)
#     expect(PseudoCleaner::Logger).not_to receive(:write)
#
#     cleaner.test_end :pseudo_delete
#
#     expect(redis.get(set_key)).not_to be
#     expect(redis.get(set_key_1)).to eq set_value
#     expect(db2_redis.get(set_key_1)).to eq set_value_1
#
#     cleaner.suite_end :pseudo_delete
#   end
#
#   it "warns of existing values changed during test" do
#     cleaner = PseudoCleaner::RedisMonitorCleaner.new(:suite_start, :suite_end, redis, {})
#
#     redis.set(set_key_1, set_value)
#
#     cleaner.suite_start :pseudo_delete
#     cleaner.test_start :pseudo_delete
#
#     redis.set(set_key_1, set_value_1)
#     redis.set(set_key, set_value)
#     db2_redis.set(set_key_1, set_value_1)
#
#     expect(PseudoCleaner::Logger).to receive(:write).exactly(4).times.and_call_original
#
#     cleaner.test_end :pseudo_delete
#
#     expect(redis.get(set_key)).not_to be
#     expect(redis.get(set_key_1)).to eq set_value_1
#     expect(db2_redis.get(set_key_1)).to eq set_value_1
#
#     cleaner.suite_end :pseudo_delete
#   end
#
#   it "warns of deleted values at suite_end" do
#     cleaner = PseudoCleaner::RedisMonitorCleaner.new(:suite_start, :suite_end, redis, {})
#
#     redis.set(set_key_1, set_value)
#
#     cleaner.suite_start :pseudo_delete
#     cleaner.test_start :pseudo_delete
#
#     redis.del(set_key_1)
#     redis.set(set_key, set_value)
#     db2_redis.set(set_key_1, set_value_1)
#
#     expect(PseudoCleaner::Logger).to receive(:write).exactly(2).times.and_call_original
#
#     cleaner.test_end :pseudo_delete
#
#     expect(redis.get(set_key)).not_to be
#     expect(redis.get(set_key_1)).not_to be
#     expect(db2_redis.get(set_key_1)).to eq set_value_1
#
#     expect(PseudoCleaner::Logger).to receive(:write).exactly(4).times.and_call_original
#
#     cleaner.suite_end :pseudo_delete
#   end
#
#   it "warns of extra values at suite_end" do
#     cleaner = PseudoCleaner::RedisMonitorCleaner.new(:suite_start, :suite_end, redis, {})
#
#     redis.set(set_key_1, set_value)
#
#     cleaner.suite_start :pseudo_delete
#     cleaner.test_start :pseudo_delete
#
#     redis.set(set_key, set_value)
#     db2_redis.set(set_key_1, set_value_1)
#
#     cleaner.test_end :pseudo_delete
#
#     expect(redis.get(set_key)).not_to be
#     expect(redis.get(set_key_1)).to eq set_value
#     expect(db2_redis.get(set_key_1)).to eq set_value_1
#
#     redis.set(set_key, set_value)
#
#     expect(PseudoCleaner::Logger).to receive(:write).exactly(2).times.and_call_original
#
#     cleaner.suite_end :pseudo_delete
#
#     expect(redis.get(set_key)).not_to be
#   end
# end