require "#{File.dirname(__FILE__)}/spec_setup"
require 'rack/cache/context'

describe "Rack::Cache::Context logging" do

  before(:each) do
    respond_with 200
    @errors = StringIO.new
    @cache = Rack::Cache::Context.new(@app)
    @cache.errors = @errors
    @cache.metaclass.send :public, :log, :warn
  end

  it 'responds to #log by writing message to #errors' do
    @cache.log :test, 'is this thing on?'
    @errors.string.should.be == "[cache] test: is this thing on?\n"
  end

  it 'allows printf formatting arguments' do
    @cache.log :test, '%s %p %i %x', 'hello', 'goodbye', 42, 66
    @errors.string.should.be == "[cache] test: hello \"goodbye\" 42 42\n"
  end

  it 'responds to #warn by logging an :warn message' do
    @cache.warn 'kinda/maybe bad stuff'
    @errors.string.should.be == "[cache] warn: kinda/maybe bad stuff\n"
  end
end
