RSpec.configure do |config|
  config.before(:suite) do
    PseudoCleaner::MasterCleaner.reset_database

    # We start suite in case a custom cleaner wants/needs to.
    DatabaseCleaner.strategy = :transaction
  end

  config.after(:suite) do
    # We end suite in case a custom cleaner wants/needs to.
    PseudoCleaner::MasterCleaner.end_suite
  end

  config.before(:each) do |example|
    example = examle.example if example.respond_to?(:example)

    pseudo_cleaner_data                     = {}
    pseudo_cleaner_data[:original_strategy] = :transaction

    new_strategy = example.metadata[:strategy]

    if new_strategy && !PseudoCleaner::MasterCleaner::CLEANING_STRATEGIES.include?(new_strategy)
      if new_strategy == :truncation
        new_strategy = :full_truncate
      elsif new_strategy == :deletion
        new_strategy = :full_delete
      else
        PseudoCleaner::Logger.write "*** Unknown/invalid cleaning strategy #{example.metadata[:strategy]}.  Using default: :transaction ***".red.on_light_white
        new_strategy = :transaction
      end
    end
    if example.metadata[:js]
      new_strategy ||= :pseudo_delete
      new_strategy = :pseudo_delete if new_strategy == :transaction
    end
    new_strategy                        ||= :transaction
    pseudo_cleaner_data[:test_strategy] = new_strategy

    unless new_strategy == :none
      DatabaseCleaner.strategy = PseudoCleaner::MasterCleaner::DB_CLEANER_CLEANING_STRATEGIES[new_strategy]
      unless new_strategy == :pseudo_delete
        DatabaseCleaner.start
      end

      pseudo_cleaner_data[:pseudo_state] = PseudoCleaner::MasterCleaner.start_test new_strategy
    end

    example.instance_variable_set(:@pseudo_cleaner_data, pseudo_cleaner_data)
  end

  config.after(:each) do |example|
    example = examle.example if example.respond_to?(:example)

    pseudo_cleaner_data = example.instance_variable_get(:@pseudo_cleaner_data)

    unless pseudo_cleaner_data[:test_strategy] == :none
      unless pseudo_cleaner_data[:test_strategy] == :pseudo_delete
        DatabaseCleaner.clean
      end

      case pseudo_cleaner_data[:test_strategy]
        when :full_delete, :full_truncate
          PseudoCleaner::MasterCleaner.database_reset
      end

      pseudo_cleaner_data[:pseudo_state].end
    end

    DatabaseCleaner.strategy = pseudo_cleaner_data[:original_strategy]
  end
end