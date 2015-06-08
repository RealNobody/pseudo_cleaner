require "rails_helper"
require "pseudo_cleaner/redis_cleaner"

RSpec.describe PseudoCleaner::RedisCleaner do
  subject { described_class.new(:suite_start, :suite_end, Redis.current, {}) }
  let(:server_subject) { subject }

  describe "common behaviours" do
    it_behaves_like "it stores and retrieves values for RedisCleaner"
  end

  describe "cleaner behaviours" do
    it_behaves_like "it tracks changes to Redis"
  end
end