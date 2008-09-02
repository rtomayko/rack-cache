require "#{File.dirname(__FILE__)}/spec_setup"
require 'rack/cache/options'

class MockOptions
  include Rack::Cache::Options

  alias_method :initialize, :initialize_options

  attr_accessor :foo

end

describe 'Rack::Cache::Options' do

  before { @options = MockOptions.new }

  describe '#set' do
    it 'sets existing options' do
      @options.set :foo, 'bar'
      @options.foo.should.be == 'bar'
    end
    it 'fails setting non-existing option' do
      lambda { @options.set :bar, 'foo' }.should.raise NoMethodError
    end
    it 'sets non-existing options when given a Proc' do
      @options.set :bar, Proc.new { 'foo' }
      @options.bar.should.be == 'foo'
    end
    it 'sets non-existing options when given a proc' do
      @options.set :bar, proc { 'foo' }
      @options.bar.should.be == 'foo'
    end
    it 'sets non-existing options when given a lambda' do
      @options.set :bar, lambda { 'foo' }
      @options.bar.should.be == 'foo'
    end
    it 'sets all key/value pairs when given a Hash' do
      @options.set :foo => 'bar',
        :bar => proc{ 'baz' }
      @options.foo.should.be == 'bar'
      @options.bar.should.be == 'baz'
    end
  end

  it 'allows setting multiple options via assignment' do
    @options.options = { :foo => 'bar', :bar => proc{ 'baz' } }
    @options.foo.should.be == 'bar'
    @options.bar.should.be == 'baz'
  end

  it 'allows the entity store to be configured' do
    @options.should.respond_to :entity_store
    @options.should.respond_to :entity_store=
    @options.entity_store.should.not.be nil
  end

  it 'allows log verbosity to be configured' do
    @options.should.respond_to :verbose
    @options.should.respond_to :verbose=
    @options.verbose.should.not.be.nil
  end

end
