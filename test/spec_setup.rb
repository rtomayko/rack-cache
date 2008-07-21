require 'pp'
require 'tmpdir'

[ STDOUT, STDERR ].each { |io| io.sync = true }

begin
  require 'test/spec'
rescue LoadError => boom
  require 'rubygems' rescue nil
  require 'test/spec'
end

begin
  require 'rack/cache'
rescue LoadError => boom
  $:.unshift File.join(File.dirname(File.dirname(__FILE__)), 'lib')
  require 'rack/cache'
end

class Test::Spec::Should
end

module TestHelpers

  include FileUtils

  F = File

  @@temp_dir_count = 0

  def create_temp_directory
    @@temp_dir_count += 1
    path = F.join(Dir.tmpdir, "rcl-#{$$}-#{@@temp_dir_count}")
    mkdir_p path
    if block_given?
      yield path
      remove_entry_secure path
    end
    path
  end

  def create_temp_file(root, file, data='')
    path = F.join(root, file)
    mkdir_p F.dirname(path)
    F.open(path, 'w') { |io| io.write(data) }
  end

  Test::Unit::TestCase.send :include, self
end
