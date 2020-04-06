require_relative 'test_helper'
require 'rack/cache/key'

describe Rack::Cache::Key do
  def mock_request(*args)
    uri, opts = args
    env = Rack::MockRequest.env_for(uri, opts || {})
    Rack::Cache::Request.new(env)
  end

  def new_key(request)
    Rack::Cache::Key.call(request)
  end

  def with_query_string_ignore(proc)
    Rack::Cache::Key.query_string_ignore = proc
    yield
  ensure
    Rack::Cache::Key.query_string_ignore = nil
  end

  it "sorts params" do
    request = mock_request('/test?z=last&a=first')
    new_key(request).must_include('a=first&z=last')
  end

  it "handles badly encoded params" do
    request = mock_request('/test?%D0%BA=%D1')
    new_key(request).must_include('%D0%BA=%D1')
  end

  it "doesn't confuse encoded equals sign with query string separator" do
    request = mock_request('/test?weird%3Dkey=whatever')
    new_key(request).must_include('weird%3Dkey=whatever')
  end

  it "includes the scheme" do
    request = mock_request(
      '/test',
      'rack.url_scheme' => 'https',
      'HTTP_HOST' => 'www2.example.org'
    )
    new_key(request).must_include('https://')
  end

  it "includes host" do
    request = mock_request('/test', "HTTP_HOST" => 'www2.example.org')
    new_key(request).must_include('www2.example.org')
  end

  it "includes path" do
    request = mock_request('/test')
    new_key(request).must_include('/test')
  end

  it "does not include question mark if there is no query string" do
    request = mock_request('/test')
    new_key(request).wont_include('?')
  end

  it "sorts the query string by key/value after decoding" do
    request = mock_request('/test?x=q&a=b&%78=c')
    new_key(request).must_match(/\?a=b&x=c&x=q$/)
  end

  it "is in order of scheme, host, path, params" do
    request = mock_request('/test?x=y', "HTTP_HOST" => 'www2.example.org')
    new_key(request).must_equal "http://www2.example.org/test?x=y"
  end

  it "ignores params based on configuration" do
    with_query_string_ignore proc { |k, _v| k == 'a' } do
      request = mock_request('/test?a=first&z=last')
      new_key(request).wont_include('a=first')
      new_key(request).must_include('z=last')
    end
  end

  it "does not include query when all params are ignored" do
    with_query_string_ignore proc { |k, _v| k == 'a' } do
      request = mock_request('/test?a=a')
      new_key(request).wont_include('?')
    end
  end
end
