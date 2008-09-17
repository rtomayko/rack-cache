require "#{File.dirname(__FILE__)}/spec_setup"
require 'rack/utils/environment_headers'

describe 'Rack::Utils::EnvironmentHeaders' do

  before :each do
    @now = Time.now.httpdate
    @env = {
      'CONTENT_TYPE'           => 'text/plain',
      'CONTENT_LENGTH'         => '0x1A4',
      'HTTP_X_FOO'             => 'BAR',
      'HTTP_IF_MODIFIED_SINCE' => @now,
      'rack.run_once'          => true
    }
    @h = Rack::Utils::EnvironmentHeaders.new(@env)
  end

  after(:each) {
    @env, @h = nil, nil
  }

  it 'retrieves headers with #[]' do
    @h.should.respond_to :[]
    @h['X-Foo'].should.be == 'BAR'
    @h['If-Modified-Since'].should.be == @now
  end

  it 'sets headers with #[]=' do
    @h.should.respond_to :[]=
    @h['X-Foo'] = 'BAZZLE'
    @h['X-Foo'].should.be == 'BAZZLE'
  end

  it 'sets values on the underlying environment hash' do
    @h['X-Something-Else'] = 'FOO'
    @env['HTTP_X_SOMETHING_ELSE'].should.be == 'FOO'
  end

  it 'handles Content-Type special case' do
    @h['Content-Type'].should.be == 'text/plain'
  end

  it 'handles Content-Length special case' do
    @h['Content-Length'].should.be == '0x1A4'
  end

  it 'implements #include? with RFC 2616 header name' do
    @h.should.include 'If-Modified-Since'
  end

  it 'deletes underlying env entries' do
    @h.delete('X-Foo')
    @env.should.not.include? 'HTTP_X_FOO'
  end

  it 'returns the underlying environment hash with #to_env' do
    @h.to_env.should.be @env
  end

  it 'iterates over all headers with #each' do
    hash = {}
    @h.each { |name,value| hash[name] = value }
    hash.should.be == {
      'Content-Type'           => 'text/plain',
      'Content-Length'         => '0x1A4',
      'X-Foo'                  => 'BAR',
      'If-Modified-Since'      => @now
    }
  end

end
