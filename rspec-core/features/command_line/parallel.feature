Feature: `--parallel` option

  Use the `--parallel` option (or `-j`) to run your suite in several worker
  processes, using all the cores of your machine. RSpec loads your suite once,
  then forks one worker per physical CPU core (or the number of workers you
  give, for example `--parallel 4` or `-j4`). Groups are handed out to the
  workers as they become available, longest first, and the results are
  reported exactly like a sequential run: formatters, `--only-failures`,
  `--profile`, `--fail-fast` and exit codes all work as usual, and the output
  of each group is kept together.

  Every worker is a separate process, so examples running at the same time
  never share global state such as constants, stubs or database connections.
  External resources such as databases or files must not be shared though:
  each worker gets a `TEST_ENV_NUMBER` environment variable (`""` for the
  first worker, then `"2"`, `"3"`...) and runs `parallel_worker_setup` hooks
  which you can use to give every worker its own resources. Since workers are
  forked once the suite is loaded, values computed while loading it (such as
  a constant holding a directory) are the same in every worker. In Rails apps,
  every worker gets its own database, as with `rails test` in parallel.
  `before(:suite)`, `after(:suite)` and `at_exit` hooks run in each worker
  (with SimpleCov, use `SimpleCov.enable_for_subprocesses true` to collect the
  coverage of all the workers).

  To keep the run time balanced, a group expected to take longer than a
  worker's share of the suite is split into its child groups and parts of its
  examples, which can run at the same time in different workers, unless it
  has `before(:context)` or `after(:context)` hooks of its own (see
  `config.parallel_split_groups_with_context_hooks`) or it is tagged with
  `:parallel_split => false`. The run time of every example is saved in
  `tmp/rspec_parallel_run_times.txt` (see `config.parallel_run_times_file_path`)
  so that the next runs hand out the longest groups first; without it, groups
  are split into smaller parts.

  Parallel runs need `Process.fork`, so on platforms which do not support it
  (JRuby, Windows) the suite runs sequentially.

  Background:
    Given a file named "spec/first_spec.rb" with:
      """ruby
      RSpec.describe "First group" do
        it "passes" do
          expect(1 + 1).to eq(2)
        end

        it "fails" do
          expect(1 + 1).to eq(3)
        end
      end
      """
    And a file named "spec/second_spec.rb" with:
      """ruby
      RSpec.describe "Second group" do
        it "runs in a worker" do
          expect(RSpec.configuration.parallel_worker_number).to be_a(Integer)
        end
      end
      """

  Scenario: Running the suite in parallel
    When I run `rspec --parallel 2 --order defined`
    Then the output should contain "3 examples, 1 failure"
    And the output should contain:
      """
      Failures:

        1) First group fails
      """
    And the exit status should be 1

  Scenario: Giving each worker its own resources
    Given a file named "spec/spec_helper.rb" with:
      """ruby
      RSpec.configure do |config|
        config.parallel_worker_setup do |worker_number|
          # e.g. connect to a database named after `ENV["TEST_ENV_NUMBER"]`
          puts "worker #{worker_number} uses TEST_ENV_NUMBER=#{ENV['TEST_ENV_NUMBER'].inspect}"
        end
      end
      """
    When I run `rspec --require spec_helper --parallel 2 --order defined`
    Then the output should contain:
      """
      worker 1 uses TEST_ENV_NUMBER=""
      """
    And the output should contain:
      """
      worker 2 uses TEST_ENV_NUMBER="2"
      """
    And the output should contain "3 examples, 1 failure"
