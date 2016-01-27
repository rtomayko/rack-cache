require_relative 'test_helper'

def dumb_app(env)
  body = block_given? ? [yield] : ['Hi']
  [ 200, {'Content-Type' => 'text/plain'}, body ]
end

describe Rack::Cache do
  before { @app = method(:dumb_app) }

  it 'takes a backend and returns a middleware component' do
    assert Rack::Cache.new(@app).respond_to? :call
  end

  it 'takes an options Hash' do
    Rack::Cache.new(@app, {})
  end

  it 'sets options provided in the options Hash' do
    object = Rack::Cache.new(@app, :foo => 'bar', 'foo.bar' => 'bling')
    object.options['foo.bar'].must_equal 'bling'
    object.options['rack-cache.foo'].must_equal 'bar'
  end

  it 'takes a block; executes it during initialization' do
    state, object = 'not invoked', nil
    instance =
      Rack::Cache.new @app do |cache|
        object = cache
        state = 'invoked'
        assert cache.respond_to? :set
      end
    state.must_equal 'invoked'
    object.must_equal instance
  end
end
