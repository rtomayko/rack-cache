require "#{File.dirname(__FILE__)}/spec_setup"

def dumb_app(env)
  body = block_given? ? [yield] : ['Hi']
  [ 200, {'Content-Type' => 'text/plain'}, body ]
end

describe 'Rack::Cache::new' do
  before { @app = method(:dumb_app) }

  it 'takes a backend and returns a middleware component' do
    Rack::Cache.new(@app).
      should.respond_to :call
  end

  it 'takes an options Hash' do
    lambda { Rack::Cache.new(@app, {}) }.
      should.not.raise(ArgumentError)
  end

  it 'sets options provided in the options Hash' do
    object = Rack::Cache.new(@app, :foo => 'bar', 'foo.bar' => 'bling')
    object.options['foo.bar'].should.equal 'bling'
    object.options['rack-cache.foo'].should.equal 'bar'
  end

  it 'takes a block; executes it during initialization' do
    state, block_scope = 'not invoked', nil
    object =
      Rack::Cache.new @app do
        block_scope = self
        state = 'invoked'
        should.respond_to :set
      end
    state.should.equal 'invoked'
    object.should.be block_scope
  end
end
