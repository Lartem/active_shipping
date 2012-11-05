require 'bundler'
Bundler::GemHelper.install_tasks

require 'rake/testtask'

namespace :test do
  #All unit tests
  Rake::TestTask.new(:units) do |t|
    t.libs << "test"
    t.pattern = 'test/unit/**/*_test.rb'
    t.verbose = true
  end

  #All remote tests
  Rake::TestTask.new(:remote) do |t|
    t.libs << "test"
    t.pattern = 'test/remote/*_test.rb'
    t.verbose = true
  end

  #FedEx
  #FedEx unit tests
  Rake::TestTask.new(:units_fedex) do |t|
    t.libs << "test"
    t.pattern = 'test/unit/**/fedex_test.rb'
    t.verbose = true
  end

  #FedEx remote tests
  Rake::TestTask.new(:remote_fedex) do |t|
    t.libs << "test"
    t.pattern = 'test/remote/fedex_test.rb'
    t.verbose = true
  end

  Rake::TestTask.new(:production_fedex) do |t|
    t.libs << "test"
    t.pattern = 'test/remote/fedex_prod_test.rb'
    t.verbose = true
  end

  #UPS
  #UPS unit tests
  Rake::TestTask.new(:units_ups) do |t|
    t.libs << "test"
    t.pattern = 'test/unit/**/ups_test.rb'
    t.verbose = true
  end

  Rake::TestTask.new(:remote_ups) do |t|
    t.libs << "test"
    t.pattern = 'test/remote/ups_test.rb'
    t.verbose = true
  end
end

desc "Default Task"
task :default => 'test:units'

desc "Run the unit and remote tests"
task :test => ['test:units','test:remote']
