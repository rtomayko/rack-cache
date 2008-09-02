require 'pp'
require 'tmpdir'

[ STDOUT, STDERR ].each { |io| io.sync = true }

begin
  require 'test/spec'
rescue LoadError => boom
  require 'rubygems' rescue nil
  require 'test/spec'
end

$LOAD_PATH.unshift File.dirname(File.dirname(__FILE__)) + '/lib'
$LOAD_PATH.unshift File.dirname(__FILE__)

require 'rack/cache'

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

end

module RequestHelpers

  def request(method, uri='/', opts={})
    opts = { 'rack.run_once' => true }.merge(opts)
    @backend ||= @app
    @context ||= Rack::Cache::Context.new(@backend)
    @request = Rack::MockRequest.new(@context)
    yield @context if block_given?
    @response = @request.send(method, uri, opts)
    @response.should.not.be.nil
    @response
  end

  def get(stem, env={}, &b)
    request(:get, stem, env, &b)
  end

  def post(*args, &b)
    request(:post, *args, &b)
  end

end

Test::Unit::TestCase.send :include, TestHelpers
Test::Unit::TestCase.send :include, RequestHelpers
