require "rails_helper"
require "pseudo_cleaner/redis_based_redis_cleaner"

RSpec.describe PseudoCleaner::RedisBasedRedisCleaner do
  context "server and client are the same object" do
    subject { described_class.new(:suite_start, :suite_end, Redis.current, {}) }
    let(:server_subject) { subject }

    describe "common behaviours" do
      it_behaves_like "it stores and retrieves values for RedisCleaner"
    end

    describe "cleaner behaviours" do
      it_behaves_like "it tracks changes to Redis"
    end
  end

  context "server and client are different objects" do
    subject { described_class.new(:suite_start, :suite_end, Redis.current, {}) }
    let(:server_subject) { described_class.new(:suite_start, :suite_end, Redis.current, {}) }

    before(:each) do
      server_subject
      subject
    end

    describe "common behaviours" do
      it_behaves_like "it stores and retrieves values for RedisCleaner"
    end

    describe "cleaner behaviours" do
      it_behaves_like "it tracks changes to Redis"
    end
  end
end