require "#{File.dirname(__FILE__)}/spec_setup"

def dumb_app(env)
  body = block_given? ? [yield] : ['Hi']
  [ 200, {'Content-Type' => 'text/plain'}, body ]
end

describe 'Rack::Cache' do
  it 'has a Request class' do
    Rack::Cache::Request.should.be.kind_of Class
  end
  it 'has a Response class' do
    Rack::Cache::Response.should.be.kind_of Class
  end
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
  it 'takes a block; executes it during initialization' do
    state, block_scope = 'not invoked', nil
    object =
      Rack::Cache.new @app do
        block_scope = self
        state = 'invoked'
        should.respond_to :on
      end
    state.should.be == 'invoked'
    object.should.be block_scope
  end
end
