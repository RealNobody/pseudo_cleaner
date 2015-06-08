RSpec.shared_examples("it stores and retrieves values for RedisCleaner") do
  let(:value_name) { "@#{Faker::Lorem.words(rand(5..10)).join("_")}".to_sym }
  let(:boolean_value) { [true, false].sample }
  let(:array_values) do
    rand(5..10).times.map do
      rand(1..10).times.map do
        Faker::Lorem.sentence
      end
    end
  end
  let(:array_values_with_hashes) do
    rand(5..10).times.map do
      rand(1..5).times.map do
        Faker::Lorem.sentence
      end
      rand(1..5).times.map do
        rand(1..10).times.reduce({}) do |hash, index|
          hash[Faker::Lorem.word] = Faker::Lorem.sentence
          hash
        end
      end
    end.sample(1_000)
  end
  let(:set_values) do
    rand(5..10).times.map do
      Faker::Lorem.sentence
    end.uniq
  end
  let(:other_set_values) do
    rand(5..10).times.map do
      Faker::Lorem.sentence
    end.uniq - set_values
  end

  around(:each) do |example_proxy|
    initial_values = subject.redis.keys

    example_proxy.call

    final_values = subject.redis.keys

    new_values = final_values - initial_values

    expect(new_values).to be_empty
  end

  after(:each) do
    subject.suite_end :pseudo_delete
  end

  describe "boolean functions" do
    after(:each) do
      server_subject.redis.del server_subject.bool_name(value_name)
    end

    it "can write then read a true value" do
      server_subject.set_value_bool value_name, true

      expect(subject.get_value_bool(value_name)).to be_truthy
    end

    it "can write then read a false value" do
      server_subject.set_value_bool value_name, false

      expect(subject.get_value_bool(value_name)).to be_falsey
    end

    it "can change a value" do
      server_subject.set_value_bool value_name, boolean_value

      expect(subject.get_value_bool(value_name)).to eq boolean_value

      server_subject.set_value_bool value_name, !boolean_value

      expect(subject.get_value_bool(value_name)).to eq !boolean_value
    end
  end

  describe "list values" do
    after(:each) do
      server_subject.clear_list_array(value_name)
    end

    context "simple string values" do
      it "clears the list" do
        server_subject.clear_list_array(value_name)
        expect(subject.get_list_array(value_name)).to eq []
      end

      it "clears a list with values" do
        server_subject.clear_list_array(value_name)

        array_values.each do |array_value|
          server_subject.append_list_value_array value_name, array_value
        end

        server_subject.clear_list_array(value_name)
        expect(subject.get_list_array(value_name)).to eq []
      end

      it "sets values in the list" do
        server_subject.clear_list_array(value_name)

        array_values.each do |array_value|
          server_subject.append_list_value_array value_name, array_value
        end

        stored_list = subject.get_list_array(value_name)

        expect(stored_list).to eq array_values
      end

      it "gets the list length" do
        server_subject.clear_list_array(value_name)

        array_values.each do |array_value|
          server_subject.append_list_value_array value_name, array_value
        end

        expect(subject.get_list_length(value_name)).to eq array_values.length
      end
    end

    context "values with hashes" do
      it "clears the list" do
        server_subject.clear_list_array(value_name)
        expect(subject.get_list_array(value_name)).to eq []
      end

      it "clears a list with values" do
        server_subject.clear_list_array(value_name)

        array_values_with_hashes.each do |array_value|
          server_subject.append_list_value_array value_name, array_value
        end

        server_subject.clear_list_array(value_name)
        expect(subject.get_list_array(value_name)).to eq []
      end

      it "sets values in the list" do
        server_subject.clear_list_array(value_name)

        array_values_with_hashes.each do |array_value|
          server_subject.append_list_value_array value_name, array_value
        end

        stored_list = subject.get_list_array(value_name)

        expect(stored_list).to eq array_values_with_hashes
      end

      it "gets the list length" do
        server_subject.clear_list_array(value_name)

        array_values_with_hashes.each do |array_value|
          server_subject.append_list_value_array value_name, array_value
        end

        expect(subject.get_list_length(value_name)).to eq array_values_with_hashes.length
      end
    end
  end

  describe "set values" do
    after(:each) do
      server_subject.clear_set(value_name)
    end

    describe "#clear_set" do
      it "clears the set" do
        server_subject.clear_set(value_name)

        expect(subject.get_set(value_name)).to be_a(SortedSet)
        expect(subject.get_set(value_name)).to be_empty
      end

      it "clears a set with values" do
        server_subject.clear_set(value_name)

        set_values.each do |set_value|
          server_subject.add_set_value(value_name, set_value)
        end

        server_subject.clear_set(value_name)

        expect(subject.get_set(value_name)).to be_a(SortedSet)
        expect(subject.get_set(value_name)).to be_empty
      end

      it "initalizes a set with values" do
        server_subject.clear_set(value_name, set_values)

        stored_set = subject.get_set(value_name)
        expect(stored_set).to be_a(SortedSet)
        expect(stored_set).not_to be_empty

        expect(stored_set.length).to eq set_values.length
        set_values.each do |set_value|
          expect(stored_set).to be_include(set_value)
        end
      end

      it "initalizes a set that has values with values" do
        server_subject.clear_set(value_name, other_set_values)
        server_subject.clear_set(value_name, set_values)

        stored_set = subject.get_set(value_name)
        expect(stored_set).to be_a(SortedSet)
        expect(stored_set).not_to be_empty

        expect(stored_set.length).to eq set_values.length
        set_values.each do |set_value|
          expect(stored_set).to be_include(set_value)
        end
      end
    end

    describe "#add_set_value" do
      it "adds a new value to the set" do
        server_subject.clear_set(value_name)

        server_subject.add_set_value(value_name, set_values[0])

        stored_set = subject.get_set(value_name)

        expect(stored_set.length).to eq 1
        expect(stored_set).to be_include(set_values[0])
      end

      it "adds a set of new values to the set" do
        server_subject.clear_set(value_name)

        set_values.each do |set_value|
          server_subject.add_set_value(value_name, set_value)
        end

        stored_set = subject.get_set(value_name)

        expect(stored_set.length).to eq set_values.length
        set_values.each do |set_value|
          expect(stored_set).to be_include(set_value)
        end
      end

      it "does not add a value more than one time" do
        server_subject.clear_set(value_name)

        set_values.each do |set_value|
          server_subject.add_set_value(value_name, set_value)
          server_subject.add_set_value(value_name, set_value)
        end
        set_values.each do |set_value|
          server_subject.add_set_value(value_name, set_value)
        end

        stored_set = subject.get_set(value_name)

        expect(stored_set.length).to eq set_values.length
        set_values.each do |set_value|
          expect(stored_set).to be_include(set_value)
        end
      end
    end

    describe "#set_includes?" do
      it "returns true if the value is in the set" do
        server_subject.clear_set(value_name, set_values)

        expect(subject.set_includes?(value_name, set_values.sample)).to be_truthy
      end

      it "returns false if the value is not in the set" do
        server_subject.clear_set(value_name, set_values)

        expect(subject.set_includes?(value_name, other_set_values.sample)).to be_falsey
      end
    end
  end
end