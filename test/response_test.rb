require "#{File.dirname(__FILE__)}/spec_setup"

describe 'Rack::Cache::Response' do

  before(:each) {
    @now = Time.now
    @response = Rack::Cache::MockResponse.new(200, {'Date' => @now.httpdate}, '')
    @one_hour_ago = Time.httpdate((Time.now - (60**2)).httpdate)
  }

  after(:each) {
    @now, @response, @one_hour_ago = nil
  }

  it 'is a subclass of Rack::Response' do
    Rack::Cache::Response.should.be < Rack::Response
  end

  it 'can be created without any args' do
    @response = Rack::Cache::Response.new
    @response.should.not.be.nil
  end

  it 'should respond to Cacheable methods' do
    @response.should.respond_to :ttl
    @response.should.respond_to :age
  end

  it 'calculates the current time with #now' do
    @response.now.to_i.should.be.close @now, 5
  end

  it 'uses the Date header for #date if present' do
    @response.headers['Date'] = @one_hour_ago.httpdate
    @response.recalculate_freshness!
    @response.date.should.be == @one_hour_ago
  end

  it 'uses the Expires header to calculate the #expires_at date' do
    @response.headers['Expires'] = @one_hour_ago.httpdate
    @response.expires_at.should.be == @one_hour_ago
  end

  it 'uses the #date to calculate the #expires_at date when no Expires header present' do
    @response.expires_at.should.be == @response.date
  end

  it 'handles Cache-Control headers with a single name=value pair' do
    @response.headers['Cache-Control'] = 'max-age=600'
    @response.cache_control['max-age'].should.be == '600'
  end

  it 'handles Cache-Control headers with multiple name=value pairs' do
    @response.headers['Cache-Control'] = 'max-age=600, max-stale=300, min-fresh=570'
    @response.cache_control['max-age'].should.be == '600'
    @response.cache_control['max-stale'].should.be == '300'
    @response.cache_control['min-fresh'].should.be == '570'
  end

  it 'handles Cache-Control headers with a single flag value' do
    @response.headers['Cache-Control'] = 'no-cache'
    @response.cache_control.should.include 'no-cache'
    @response.cache_control['no-cache'].should.be true
  end

  it 'handles Cache-Control headers with a bunch of all kinds of stuff' do
    @response.headers['Cache-Control'] = 'max-age=600,must-revalidate,min-fresh=3000,foo=bar,baz'
    @response.cache_control['max-age'].should.be == '600'
    @response.cache_control['must-revalidate'].should.be true
    @response.cache_control['min-fresh'].should.be == '3000'
    @response.cache_control['foo'].should.be == 'bar'
    @response.cache_control['baz'].should.be true
  end

  it 'responds to #must_revalidate?' do
    @response.headers['Cache-Control'] = 'must-revalidate'
    @response.should.be.must_revalidate
  end

  it 'uses Cache-Control for #max_age if present' do
    @response.headers['Cache-Control'] = 'max-age=600'
    @response.max_age.should.be == 600
  end

  it 'uses Expires for #max_age if no Cache-Control max-age present' do
    @response.headers['Cache-Control'] = 'must-revalidate'
    @response.headers['Expires'] = @one_hour_ago.httpdate
    @response.max_age.should.be.close(-(60 ** 2), 1)
  end

  it 'gives a #max_age of zero when no freshness information available' do
    @response.max_age.should.be == 0
  end

  it 'has a #ttl of zero when no Expires or Cache-Control headers present' do
    @response.ttl.should.be == 0
  end

  it 'calculates the #ttl based on the Expires header when no max-age is present' do
    @response.headers['Expires'] = (@response.now + (60**2)).httpdate
    @response.ttl.should.be.close(60**2, 1)
  end

  it 'supports negative ttl when Expires is in the past' do
    @response.headers['Expires'] = @one_hour_ago.httpdate
    @response.ttl.should.be.close(-(60**2), 1)
  end

  it 'calculates the #ttl based on the Cache-Control max-age value when present' do
    @response.headers['Cache-Control'] = 'max-age=60'
    @response.ttl.should.be.close(60, 1)
  end

  it 'allows the #ttl to be set and adjusts the #max_age accordingly' do
    @response.ttl = 600
    @response.ttl.should.be == 600
    @response.max_age.should.be == @response.age + 600
  end

  it 'allows the #max_age to be set and adjusts the #ttl accordingly' do
    @response.max_age = 600
    @response.max_age.should.be == 600
    @response.ttl.should.be == @response.age + 600
  end

end
