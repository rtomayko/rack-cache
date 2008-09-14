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

# Methods for constructing downstream applications / response
# generators.
module CacheContextHelpers

  # The Rack::Cache::Context instance used for the most recent
  # request.
  attr_reader :cache

  # An Array of Rack::Cache::Context instances used for each request, in
  # request order.
  attr_reader :caches

  # The Rack::Response instance result of the most recent request.
  attr_reader :response

  # An Array of Rack::Response instances for each request, in request order.
  attr_reader :responses

  # The backend application object.
  attr_reader :app

  def setup_cache_context
    # holds each Rack::Cache::Context
    @app = nil

    # each time a request is made, a clone of @cache_template is used
    # and appended to @caches.
    @cache_template = nil
    @cache = nil
    @caches = []
    @errors = StringIO.new

    @called = false
    @request = nil
    @response = nil
    @responses = []
  end

  def teardown_cache_context
    @app, @cache_template, @cache, @caches, @called,
    @request, @response, @responses = nil
  end

  # A basic response with 200 status code and a tiny body.
  def respond_with(status=200, headers={}, body=['Hello World'])
    called = false
    @app =
      lambda do |env|
        called = true
        response = Rack::Response.new(body, status, headers)
        request = Rack::Request.new(env)
        yield request, response if block_given?
        response.finish
      end
    @app.meta_def(:called?) { called }
    @app.meta_def(:reset!) { called = false }
    @app
  end

  def request(method, uri='/', opts={})
    opts = { 'rack.run_once' => true, 'rack.errors' => @errors }.merge(opts)

    fail 'response not specified (use respond_with)' if @app.nil?
    @app.reset! if @app.respond_to?(:reset!)

    @cache_prototype ||= Rack::Cache::Context.new(@app)
    @cache = @cache_prototype.clone
    @caches << @cache
    @request = Rack::MockRequest.new(@cache)
    yield @cache if block_given?
    @response = @request.send(method, uri, opts)
    @responses << @response
    @response
  end

  def get(stem, env={}, &b)
    request(:get, stem, env, &b)
  end

  def post(*args, &b)
    request(:post, *args, &b)
  end

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

end

class Test::Unit::TestCase
  include TestHelpers
  include CacheContextHelpers
end

# Metaid == a few simple metaclass helper
# (See http://whytheluckystiff.net/articles/seeingMetaclassesClearly.html.)
class Object
  # The hidden singleton lurks behind everyone
  def metaclass; class << self; self; end; end
  def meta_eval &blk; metaclass.instance_eval &blk; end
  # Adds methods to a metaclass
  def meta_def name, &blk
    meta_eval { define_method name, &blk }
  end
  # Defines an instance method within a class
  def class_def name, &blk
    class_eval { define_method name, &blk }
  end
end
