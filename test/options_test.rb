require "#{File.dirname(__FILE__)}/spec_setup"
require 'rack/cache/options'

module Rack::Cache::Options
  option_accessor :foo
end

class MockOptions
  include Rack::Cache::Options
  alias_method :initialize, :initialize_options
end

describe 'Rack::Cache::Options' do

  before { @options = MockOptions.new }

  describe '#set' do
    it 'sets existing options' do
      @options.set :foo, 'bar'
      @options.foo.should.be == 'bar'
    end
    it 'sets all key/value pairs when given a Hash' do
      @options.set :foo => 'bar',
        :bar => 'baz'
      @options.foo.should.be == 'bar'
      @options.options['rack-cache.bar'].should.be == 'baz'
    end
  end

  it 'allows setting multiple options via assignment' do
    @options.options = { :foo => 'bar', :bar => 'baz' }
    @options.foo.should.be == 'bar'
    @options.options['rack-cache.bar'].should.be == 'baz'
  end

  it 'allows the meta store to be configured' do
    @options.should.respond_to :metastore
    @options.should.respond_to :metastore=
    @options.metastore.should.not.be nil
  end

  it 'allows the entity store to be configured' do
    @options.should.respond_to :entitystore
    @options.should.respond_to :entitystore=
    @options.entitystore.should.not.be nil
  end

  it 'allows log verbosity to be configured' do
    @options.should.respond_to :verbose
    @options.should.respond_to :verbose=
    @options.should.respond_to :verbose?
    @options.verbose.should.not.be.nil
  end

end
