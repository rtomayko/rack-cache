require "#{File.dirname(__FILE__)}/spec_setup"
require 'rack/cache/context'

describe "Rack::Cache::Context logging" do

  before(:each) do
    respond_with 200
    @errors = StringIO.new
    @cache = Rack::Cache::Context.new(@app, 'rack-cache.errors' => @errors)
    @cache.metaclass.send :public, :log
  end

  it 'responds to #log by writing message to #errors' do
    @cache.log 'is this thing on?'
    @errors.string.should.be == "cache: is this thing on?\n"
  end

  it 'allows printf formatting arguments' do
    @cache.log '%s %p %i %x', 'hello', 'goodbye', 42, 66
    @errors.string.should.be == "cache: hello \"goodbye\" 42 42\n"
  end
end
