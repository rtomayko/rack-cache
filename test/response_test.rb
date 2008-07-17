require "#{File.dirname(__FILE__)}/spec_setup"

describe 'Rack::Cache::Response' do
  it 'is a subclass of Rack::Response' do
    Rack::Cache::Response.should.be < Rack::Response
  end

  it 'can be created without any args' do
    @response = Rack::Cache::Response.new
  end

  it 'should respond to Cacheable methods' do
    @response.should.respond_to :ttl
    @response.should.respond_to :age
  end

  before(:each) {
    @response = Rack::Cache::MockResponse.new(200, {'X-Foo' => 'Bar'}, 'FOO')
    @one_hour_ago = Time.httpdate((Time.now - (60**2)).httpdate)
  }

  after(:each) {
    @response = nil
  }

  it 'calculates the current time with #now' do
    @response.now.to_i.should.be.close Time.now, 5
  end

  it 'uses the Date header for #date if present' do
    @response.headers['Date'] = @one_hour_ago.httpdate
    @response.date.should.be == @one_hour_ago
  end

  it 'uses #now for #date when no Date header is present' do
    @response.headers['Date'].should.be.nil
    @response.date.should.be == @response.now
  end

  it 'sets the Date header to #now if no Date header is present' do
    @response.date
    @response.headers['Date'].should.be == @response.now.httpdate
  end

  it "calculates the response's #age" do
    @response.headers['Date'] = @one_hour_ago.httpdate
    @response.age.should.be.close(60**2, 5)
  end

  it 'calculates an #age of zero when no Date header present' do
    @response.age.should.be == 0
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

end
