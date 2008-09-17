require "#{File.dirname(__FILE__)}/spec_setup"

describe 'Rack::Cache::Response' do

  before(:each) {
    @now = Time.now
    @response = Rack::Cache::Response.new(200, {'Date' => @now.httpdate}, '')
    @one_hour_ago = Time.httpdate((Time.now - (60**2)).httpdate)
  }

  after(:each) {
    @now, @response, @one_hour_ago = nil
  }

  it 'responds to cache-related methods' do
    @response.should.respond_to :ttl
    @response.should.respond_to :age
    @response.should.respond_to :date
  end

  it 'responds to #to_a with a Rack response tuple' do
    @response.should.respond_to :to_a
    @response.to_a.should.be == [200, {'Date' => @now.httpdate}, '']
  end

  it 'retrieves headers with #[]' do
    @response.headers['X-Foo'] = 'bar'
    @response.should.respond_to :[]
    @response['X-Foo'].should.be == 'bar'
  end

  it 'sets headers with #[]=' do
    @response.should.respond_to :[]=
    @response['X-Foo'] = 'bar'
    @response.headers['X-Foo'].should.be == 'bar'
  end
end
