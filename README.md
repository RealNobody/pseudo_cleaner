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

Because the PsuedoCleaner already uses the [SortedSeeder gem](https://github.com/RealNobody/sorted_seeder) to determine what
order to delete records in when cleaning up, when the database is truncated, it will re-seed the database using the
SortedSeeders seed_all function.

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

Add the lines as early as possible in the spec_helper because the hooks used are before and after hooks.  Adding the 
hooks early will wrap other hooks in the transaction.

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

### Cucumber

Cucumber integration similar to Rspec integration simply add the cucumber hook file instead.

    require 'pseudo_cleaner'
    require 'pseudo_cleaner/cucumber'

### Spinach

Spinach integration hasn't been fully tested.

It probably should work.

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

### Redis Cleaner

The RedisCleaner is a base class for a Custom Cleaner you must create yourself.  The RedisCleaner is designed to work
by replacing your existing redis class with a tracking redis class.  It will track your updates as you make calls and
then clean them up when you are done.

An example implementation where the default redis used by the system is `$redis`.  (In other cases, you may want to 
use mocking to swap out the redis instance...)

This in the file:  db\cleaners\redis_cleaner.rb in the project...

    class RedisCleaner < PseudoCleaner::RedisCleaner
      attr_reader :test_ignore_regex
      attr_reader :current_ignore_regex

      BASE_IGNORE =
          [
              /rc-analytics::exports:actions:partner_last_run_dates/,
              /rack\|whitelist_cache\|hash_data/,
              /SequelModelCache/,
              /active_sessions/,
          ]

      def ignore_regexes
        current_ignore_regex
      end

      def ignore_durring_test(additional_ignore_regexes, &block)
        orig_test_ignore_regex = test_ignore_regex
        begin
          @test_ignore_regex    = [*additional_ignore_regexes, *test_ignore_regex]
          @current_ignore_regex = [*RedisCleaner::BASE_IGNORE, *test_ignore_regex]

          block.yield
        ensure
          @test_ignore_regex    = orig_test_ignore_regex
          @current_ignore_regex = [*RedisCleaner::BASE_IGNORE, *test_ignore_regex]
        end
      end

      def initialize(*args)
        super(*args)

        @current_ignore_regex = RedisCleaner::BASE_IGNORE
        @test_ignore_regex    = []
        @redis                = $redis
        $redis                = self

        Redis.current        = $redis
        Ohm.redis            = $redis
        Redis::Objects.redis = $redis
      end
    end

The main point here is that I set the value of @redis to the redis instance I want to use, and then "replace" that 
redis instance in the code with the RedisCleaner class.

## Configurations

As the system evolves, I keep adding new and different options.  Here is a summary of what some of them do at least:

* **output_diagnostics**
  Output diagnostic information at various points in the process.  This would include the level set starting point of
  a table, what rows were deleted, etc.
* **clean_database_before_tests**
  Delete all data in all tables can call SortedSeeer to re-seed the database before any tests are run.  This is 
  defaulted to false because this can be time-consuming and many automated testing systems already do this for you.
* **reset_auto_increment**
  Defaulted to true, this will set the auto-increment value for a table to the highest id + 1 when the system starts.
* **post_transaction_analysis**
  An early version of the peek-data function.  This will output information about every table at the end of the test.
  The data output will match the initial state data if `output_diagnostics` is true.
* **peek_data_on_error**
  Defaulted to true, this will output a dump of all of the new values in the database if an error occured in the test.
* **peek_data_not_on_error**
  If set to true, this will output a dump of all of the new values in the database at the end of every test.  This 
  functionality can also be achieved by tagging your test with `:full_data_dump` (RSpec) or `@full_data_dump` 
  (Cucumber and Spinach).
* **enable_full_data_dump_tag**
  Defaulted to true, this allows the `full_data_dump` tag to work.  If set to false, the tag will be ignored.
* **disable_cornucopia_output**
  If set to false, this will force all output to be done through the registered logger which defaults to simply 
  outputing data to stdout.

## Cornucopia integration

I have another gem that I use a lot called `cornucopia`.  I like it because it gives me really useful reports on what
happened in my tests.

I have updated this gem to use Cornucopia to output most of the information to be output by the gem.  You can disable
this feature by setting `disable_cornucopia_output` to true.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request