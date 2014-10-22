# PseudoCleaner

The [Database Cleaner gem](https://github.com/DatabaseCleaner/database_cleaner) is a wonderful tool,
and I've used it for years.  I would highly recommend it.  It is a well written and a well used and therefore tested
tool that you can rely on.

However, it is (quite rightly) a very conservative tool.  I often run into situations where it doesn't quite fit my
needs.  there are often times when I cannot use transactions (such as when I am doing Cucumber tests with Capybara to
feature test my site), but when truncating my tables just isn't reasonable or practical.

So, I came up with a compromise that works for a large number of tables and databases that I've worked with.  The
thing is that this solution is not like DatabaseCleaner in that it isn't conservative,
and it doesn't guarantee much.  This solution might not clean the database entirely between calls.

The thing is, the database doesn't have to be entirely clean after every call for most tests,
just clean enough is often good enough.

So, what is it that the PseudoCleaner does and why is it good enough?

The cleaner relies on the fact that most databases use 2 common defaults in most tables (well,
most tables that simple tests that rely on the workings of a cleaner anyway...)  Those features are an auto-increment
`id` column, and/or a `created_at`/`updated_at` columns.

Using these, when a test starts the cleaner iterates through the tables and saves the current `MAX(id)`,
`MAX(created_at)`, and `MAX(updated_at)` values for a table.  When a test ends, the cleaner iterates through the
tables again and deletes anything that is new.  It will then report (optionally) on any records that have been
updated but haven't been cleaned up.  In future versions, I have plans for it to also report (optionally) on any
referential integrity holes.

Because the PsuedoCleaner already uses the [Seedling gem](https://github.com/RealNobody/seedling) to determine what
order to delete records in when cleaning up, when the database is truncated, it will re-seed the database using the
Seedlings seed_all function.

## Installation

Add this line to your application's Gemfile in the test group:

    gem 'pseudo_cleaner'

OR

    gem 'pseudo_cleaner', '~> 0.0.1', :git => "git@github.com/RealNobody/pseudo_cleaner.git"

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install pseudo_cleaner

## Usage

There are multiple ways to use the PseudoCleaner.  The main intended usages are detailed here:

### Rspec

Rspect integration is built in to make using the PseudoCleaner simple and straight-forward.
To integrate the PseudoCleaner with Rspec, simply add the following lines to `spec_helper.rb`:

    require 'pseudo_cleaner'
    require 'pseudo_cleaner/rspec'

All tests will now by default use DatabaseCleaner with the `:transaction` strategy.  For most tests, this will wrap
the test in a transaction, and roll back the transaction at the end of the test.

If a test is a feature test which uses Capybara using the `:js` tag, that test will be switched to not use
DatabaseCleaner.  Instead, the test will use the `:pseudo_delete` strategy which as described will store the state of
the tables before the test then delete any new records at the end of the test.

If you want or need a specific strategy for a single test, you can specify the metadata tag: `:strategy` in the test
to change the behavior of the test.  This tag accepts the following values:

* :none - Do not use any cleaning on this test run.
* :psedu_delete - Do not use DatabaseCleaner and clean tables individually.
* :truncation - Use the :truncation strategy with DatabaseCleaner and re-seed the database after truncation.
* :deletion - Use the :deletion strategy with DatabaseCleaner and re-seed the database after deletion.
* :transaction - Use the :transaction strategy with DatabaseCleaner.

Example:

    it "is a test", strategy: :truncation do
      expect(something).to work
    end

### Capybara

Capybara integration similar to Rspec integration is planned, but not implemented yet.

### Manual

There are two ways to use the cleaner manually.  When you use the cleaner manually, you are only using the
PseduoCleaner.  You do not get DatabaseCleaner integration like you get automatically with Rspec.  This will create
table cleaners and any custom defined cleaners and execute them.

NOTE:  When using the tool manually, if the strategy is any strategy other than `:pseudo_delete`, the default
cleaners will not do anything.  The strategy may still be useful though if you have any custom cleaners.

*PseudoCleaner::MasterCleaner.clean*  This function cleans the code executed inside a block and takes two parameters.
The first parameter takes the values `:test` or `:suite`.  This is used to determine if the cleaner is wrapped around
a set of tests or a single test. The default implementations provided do not distinguish between these, but custom
cleaners might.  The second parameter is the strategy to use.

    PseudoCleaner::MasterCleaner.clean(:test, :pseudo_delete) do
      # Your code here
    end

*PseudoCleaner::MasterCleaner.start_test*  This takes one parameter that is the type of the cleaner this is (`:test` or
`:suite`).  This creates a cleaner object that can be started and ended around the code to be cleaned.  You specify
the strategy for the tests when you start the cleaner.

    pseudo_cleaner = PseudoCleaner::MasterCleaner.start_test :pseudo_delete
    # Your code here
    pseudo_cleaner.end

## Custom Cleaners

This system is built to clean the database after calls.

If you have additional actions which need to be done either before and/or after tests run to clean up resources, you
can create custom cleaners and place them in the `db/cleaners` folder.  You can also create a custom cleaner for a
specific table by placing the cleaner in the same folder and naming it `<TableName>Cleaner`.

Cleaners must be instantiated, and will be initialized with the following prototype:
`initialize(start_method, end_method, table, options = {})`

Cleaners must also include one or more of the following funcitons:

* test_start test_strategy
* test_end test_strategy
* suite_start test_strategy
* suite_end test_strategy

A Cleaner can adjust when it is called in relation to other cleaners by overriding the instance method `<=>`

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
