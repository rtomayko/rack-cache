require_relative 'test_helper'
require 'rack/cache/options'

module Rack::Cache::Options
  option_accessor :foo
end

class MockOptions
  include Rack::Cache::Options
  def initialize
    @env = nil
    initialize_options
  end
end

describe Rack::Cache::Options do
  before { @options = MockOptions.new }

  describe '#set' do
    it 'sets a Symbol option as rack-cache.symbol' do
      @options.set :bar, 'baz'
      @options.options['rack-cache.bar'].must_equal 'baz'
    end

    it 'sets a String option as string' do
      @options.set 'foo.bar', 'bling'
      @options.options['foo.bar'].must_equal 'bling'
    end

    it 'sets all key/value pairs when given a Hash' do
      @options.set :foo => 'bar', :bar => 'baz', 'foo.bar' => 'bling'
      @options.foo.must_equal 'bar'
      @options.options['rack-cache.bar'].must_equal 'baz'
      @options.options['foo.bar'].must_equal 'bling'
    end
  end

  it 'makes options declared with option_accessor available as attributes' do
    @options.set :foo, 'bar'
    @options.foo.must_equal 'bar'
  end

  it 'allows setting multiple options via assignment' do
    @options.options = { :foo => 'bar', :bar => 'baz', 'foo.bar' => 'bling' }
    @options.foo.must_equal 'bar'
    @options.options['foo.bar'].must_equal 'bling'
    @options.options['rack-cache.bar'].must_equal 'baz'
  end

  it "allows storing the value as a block" do
    block = Proc.new { "bar block" }
    @options.set(:foo, &block)
    @options.options['rack-cache.foo'].must_equal block
  end

  it 'allows the cache key generator to be configured' do
    assert @options.respond_to? :cache_key
    assert @options.respond_to? :cache_key=
  end

  it 'allows the meta store to be configured' do
    assert @options.respond_to? :metastore
    assert @options.respond_to? :metastore=
    refute @options.metastore.nil?
  end

  it 'allows the entity store to be configured' do
    assert @options.respond_to? :entitystore
    assert @options.respond_to? :entitystore=
    refute @options.entitystore.nil?
  end

  it 'allows log verbosity to be configured' do
    assert @options.respond_to? :verbose
    assert @options.respond_to? :verbose=
    assert @options.respond_to? :verbose?
    refute @options.verbose.nil?
  end
end
