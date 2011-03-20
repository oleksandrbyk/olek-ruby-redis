require 'rubygems'
require 'rake/gempackagetask'
require 'rake/testtask'

$:.unshift File.join(File.dirname(__FILE__), 'lib')
require 'redis/version'

GEM = 'redis'
GEM_NAME = 'redis'
GEM_VERSION = Redis::VERSION
AUTHORS = ['Ezra Zygmuntowicz', 'Taylor Weibley', 'Matthew Clark', 'Brian McKinney', 'Salvatore Sanfilippo', 'Luca Guidi', 'Michel Martens', 'Damian Janowski']
EMAIL = "ez@engineyard.com"
HOMEPAGE = "http://github.com/ezmobius/redis-rb"
SUMMARY = "Ruby client library for Redis, the key value storage server"

spec = Gem::Specification.new do |s|
  s.name = GEM
  s.version = GEM_VERSION
  s.platform = Gem::Platform::RUBY
  s.has_rdoc = true
  s.extra_rdoc_files = ["LICENSE"]
  s.summary = SUMMARY
  s.description = s.summary
  s.authors = AUTHORS
  s.email = EMAIL
  s.homepage = HOMEPAGE
  s.require_path = 'lib'
  s.autorequire = GEM
  s.files = %w(LICENSE README.md Rakefile) + Dir.glob("{lib,tasks,spec}/**/*")
end

REDIS_DIR = File.expand_path(File.join("..", "test"), __FILE__)
REDIS_CNF = File.join(REDIS_DIR, "test.conf")
REDIS_PID = File.join(REDIS_DIR, "db", "redis.pid")

task :default => :run

desc "Run tests and manage server start/stop"
task :run => [:start, :test, :stop]

desc "Start the Redis server"
task :start do
  redis_running = \
  begin
    File.exists?(REDIS_PID) && Process.kill(0, File.read(REDIS_PID).to_i)
  rescue Errno::ESRCH
    FileUtils.rm REDIS_PID
    false
  end

  system "redis-server #{REDIS_CNF}" unless redis_running
end

desc "Stop the Redis server"
task :stop do
  if File.exists?(REDIS_PID)
    Process.kill "INT", File.read(REDIS_PID).to_i
    FileUtils.rm REDIS_PID
  end
end

desc "Run the test suite"
task :test do
  require 'redis'
  require 'cutest'

  Cutest.run(Dir['./test/**/*_test.rb'])

  begin
    require 'redis/connection/hiredis'

    puts
    puts "Running tests against hiredis v#{Hiredis::VERSION}"

    Cutest.run(Dir['./test/**/*_test.rb'])
  rescue
    puts "Skipping tests against hiredis"
  end

  begin
    require 'redis/connection/synchrony'

    # Make cutest fiber + eventmachine aware
    undef test if defined? test
    def test(name = nil, &block)
      cutest[:test] = name

      blk = Proc.new do
        prepare.each { |blk| blk.call }
        block.call(setup && setup.call)
      end

      t = Thread.current[:cutest]
      if defined? EventMachine
        EM.synchrony do
          Thread.current[:cutest] = t
          blk.call
          EM.stop
        end
      else
        blk.call
      end
    end

    puts
    puts "Running tests against em-synchrony"

    threaded_tests = [
      './test/distributed_blocking_commands_test.rb',
      './test/distributed_publish_subscribe_test.rb',
      './test/publish_subscribe_test.rb',
      './test/remote_server_control_commands_test.rb',
      './test/thread_safety_test.rb',
      './test/error_replies_test.rb'
    ]

    Cutest.run(Dir['./test/**/*_test.rb'] - threaded_tests)
  rescue
    puts "Skipping tests against em-synchrony"
  end
end

Rake::GemPackageTask.new(spec) do |pkg|
  pkg.gem_spec = spec
end

desc "install the gem locally"
task :install => [:package] do
  sh %{gem install pkg/#{GEM}-#{GEM_VERSION}}
end

desc "create a gemspec file"
task :gemspec do
  File.open("#{GEM}.gemspec", "w") do |file|
    file.puts spec.to_ruby
  end
end

task :doc => ["doc:generate", "doc:prepare"]

namespace :doc do
  task :generate do
    require "shellwords"

    `rm -rf doc`

    current_branch = `git branch`[/^\* (.*)$/, 1]

    begin
      tags = `git tag -l`.split("\n").sort.reverse

      tags.each do |tag|
        `git checkout -q #{tag} 2>/dev/null`

        unless $?.success?
          $stderr.puts "Need a clean working copy. Please git-stash away."
          exit 1
        end

        puts tag

        `mkdir -p doc/#{tag}`

        files = `git ls-tree -r HEAD lib`.split("\n").map do |line|
          line[/\t(.*)$/, 1]
        end

        opts = [
          "--title", "A Ruby client for Redis",
          "--output", "doc/#{tag}",
          "--no-cache",
          "--no-save",
          "-q",
          *files
        ]

        `yardoc #{Shellwords.shelljoin opts}`
      end
    ensure
      `git checkout -q #{current_branch}`
    end
  end

  task :prepare do
    versions = `git tag -l`.split("\n").grep(/^v/).sort
    latest_version = versions.last

    File.open("doc/.htaccess", "w") do |file|
      file.puts "RedirectMatch 302 ^/?$ /#{latest_version}"
    end

    File.open("doc/robots.txt", "w") do |file|
      file.puts "User-Agent: *"

      (versions - [latest_version]).each do |version|
        file.puts "Disallow: /#{version}"
      end
    end

    google_analytics = <<-EOS
    <script type="text/javascript">

      var _gaq = _gaq || [];
      _gaq.push(['_setAccount', 'UA-11356145-2']);
      _gaq.push(['_trackPageview']);

      (function() {
        var ga = document.createElement('script'); ga.type = 'text/javascript'; ga.async = true;
        ga.src = ('https:' == document.location.protocol ? 'https://ssl' : 'http://www') + '.google-analytics.com/ga.js';
        var s = document.getElementsByTagName('script')[0]; s.parentNode.insertBefore(ga, s);
      })();

    </script>
    EOS

    Dir["doc/**/*.html"].each do |path|
      lines = IO.readlines(path)

      File.open(path, "w") do |file|
        lines.each do |line|
          if line.include?("</head>")
            file.write(google_analytics)
          end

          file.write(line)
        end
      end
    end
  end

  task :deploy do
    system "rsync --del -avz doc/* redis-rb.keyvalue.org:deploys/redis-rb.keyvalue.org/"
  end
end

namespace :commands do
  def redis_commands
    $redis_commands ||= doc.keys.map do |key|
      key.split(" ").first.downcase
    end.uniq
  end

  def doc
    $doc ||= begin
      require "open-uri"
      require "json"

      JSON.parse(open("https://github.com/antirez/redis-doc/raw/master/commands.json").read)
    end
  end

  def document(file)
    source = File.read(file)

    doc.each do |name, command|
      source.sub!(/(?:^ *# .*\n)*(^ *#\n(^ *# .+?\n)*)*^( *)def #{name.downcase}(\(|$)/) do
        extra_comments, indent, extra_args = $1, $3, $4
        comment = "#{indent}# #{command["summary"].strip}."

        IO.popen("par p#{2 + indent.size} 80", "r+") do |io|
          io.puts comment
          io.close_write
          comment = io.read
        end

        "#{comment}#{extra_comments}#{indent}def #{name.downcase}#{extra_args}"
      end
    end

    File.open(file, "w") { |f| f.write(source) }
  end

  task :doc do
    document "lib/redis.rb"
    document "lib/redis/distributed.rb"
  end

  task :verify do
    require "redis"
    require "stringio"

    require "./test/helper"

    OPTIONS[:logger] = Logger.new("./tmp/log")

    Rake::Task["test"].invoke

    redis = Redis.new

    report = ["Command", "\033[0mDefined?\033[0m", "\033[0mTested?\033[0m"]

    yes, no = "\033[1;32mYes\033[0m", "\033[1;31mNo\033[0m"

    log = File.read("./tmp/log")

    redis_commands.sort.each do |name, _|
      defined, tested = redis.respond_to?(name), log[">> #{name.upcase}"]

      next if defined && tested

      report << name
      report << (defined ? yes : no)
      report << (tested ? yes : no)
    end

    IO.popen("rs 0 3", "w") do |io|
      io.puts report.join("\n")
    end
  end
end
