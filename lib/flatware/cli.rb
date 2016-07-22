require 'thor'
require 'flatware/pids'
module Flatware
  class CLI < Thor

    def self.processors
      @processors ||= ProcessorInfo.count
    end

    def self.worker_option
      method_option :workers, aliases: "-w", type: :numeric, default: processors, desc: "Number of concurent processes to run"
    end

    class_option :log, aliases: "-l", type: :boolean, desc: "Print debug messages to $stderr"

    worker_option
    method_option 'formatters', aliases: "-f", type: :array, default: %w[console], desc: "The formatters to use for output"
    method_option 'dispatch-endpoint', type: :string, default: 'ipc://dispatch'
    method_option 'sink-endpoint', type: :string, default: 'ipc://task'
    desc "cucumber [FLATWARE_OPTS] [CUCUMBER_ARGS]", "parallelizes cucumber with custom arguments"
    def cucumber(*args)
      require 'flatware/cucumber'
      config = Cucumber.configure args

      unless config.jobs.any?
        puts "Please create some feature files in the #{config.feature_dir} directory."
        exit 1
      end

      Flatware.verbose = options[:log]
      Worker.spawn count: workers, runner: Cucumber, dispatch: options['dispatch-endpoint'], sink: options['sink-endpoint']
      start_sink jobs: config.jobs, workers: workers
    end

    worker_option
    method_option 'formatters', aliases: "-f", type: :array, default: %w[console], desc: "The formatters to use for output"
    method_option 'dispatch-endpoint', type: :string, default: 'ipc://dispatch'
    method_option 'sink-endpoint', type: :string, default: 'ipc://task'
    desc "rspec [FLATWARE_OPTS]", "parallelizes rspec"
    def rspec(*rspec_args)
      require 'flatware/rspec'
      jobs = RSpec.extract_jobs_from_args rspec_args, workers: workers
      Flatware.verbose = options[:log]
      Worker.spawn count: workers, runner: RSpec, dispatch: options['dispatch-endpoint'], sink: options['sink-endpoint']
      start_sink jobs: jobs, workers: workers
    end

    worker_option
    desc "fan [COMMAND]", "executes the given job on all of the workers"
    def fan(*command)
      Flatware.verbose = options[:log]

      command = command.join(" ")
      puts "Running '#{command}' on #{workers} workers"

      workers.times do |i|
        fork do
          exec({"TEST_ENV_NUMBER" => i.to_s}, command)
        end
      end
      Process.waitall
    end

    desc "clear", "kills all flatware processes"
    def clear
      (Flatware.pids - [$$]).each do |pid|
        Process.kill 6, pid
      end
    end

    private

    def start_sink(jobs:, workers:, runner: current_command_chain.first)
     $0 = 'flatware sink'
      Process.setpgrp
      formatter = Formatters.load_by_name(runner, options['formatters'])
      passed = Sink.start_server jobs: jobs, formatter: formatter, sink: options['sink-endpoint'], dispatch: options['dispatch-endpoint'], worker_count: workers
      exit passed ? 0 : 1
    end

    def log(*args)
      Flatware.log(*args)
    end

    def workers
      options[:workers]
    end
  end
end
