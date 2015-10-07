require "#{File.dirname(__FILE__)}/spec_setup"
require 'rack/cache/cachecontrol'
require 'rack/cache/metastore'

describe 'Rack::Cache::CacheControl' do
  it 'takes no args and initializes with an empty set of values' do
    cache_control = Rack::Cache::CacheControl.new
    assert cache_control.empty?
    cache_control.to_s.must_equal ''
  end

  it 'takes a String and parses it into a Hash when created' do
    cache_control = Rack::Cache::CacheControl.new('max-age=600, foo')
    cache_control['max-age'].must_equal '600'
    cache_control['foo'].must_equal true
  end

  it 'takes a String with a single name=value pair' do
    cache_control = Rack::Cache::CacheControl.new('max-age=600')
    cache_control['max-age'].must_equal '600'
  end

  it 'takes a String with multiple name=value pairs' do
    cache_control = Rack::Cache::CacheControl.new('max-age=600, max-stale=300, min-fresh=570')
    cache_control['max-age'].must_equal '600'
    cache_control['max-stale'].must_equal '300'
    cache_control['min-fresh'].must_equal '570'
  end

  it 'takes a String with a single flag value' do
    cache_control = Rack::Cache::CacheControl.new('no-cache')
    cache_control.must_include 'no-cache'
    cache_control['no-cache'].must_equal true
  end

  it 'takes a String with a bunch of all kinds of stuff' do
    cache_control =
      Rack::Cache::CacheControl.new('max-age=600,must-revalidate,min-fresh=3000,foo=bar,baz')
    cache_control['max-age'].must_equal '600'
    cache_control['must-revalidate'].must_equal true
    cache_control['min-fresh'].must_equal '3000'
    cache_control['foo'].must_equal 'bar'
    cache_control['baz'].must_equal true
  end

  it 'strips leading and trailing spaces from header value' do
    cache_control = Rack::Cache::CacheControl.new('   public,   max-age =   600  ')
    cache_control.must_include 'public'
    cache_control.must_include 'max-age'
    cache_control['max-age'].must_equal '600'
  end

  it 'strips blank segments' do
    cache_control = Rack::Cache::CacheControl.new('max-age=600,,max-stale=300')
    cache_control['max-age'].must_equal '600'
    cache_control['max-stale'].must_equal '300'
  end

  it 'removes all directives with #clear' do
    cache_control = Rack::Cache::CacheControl.new('max-age=600, must-revalidate')
    cache_control.clear
    assert cache_control.empty?
  end

  it 'converts self into header String with #to_s' do
    cache_control = Rack::Cache::CacheControl.new
    cache_control['public'] = true
    cache_control['max-age'] = '600'
    cache_control.to_s.split(', ').sort.must_equal ['max-age=600', 'public']
  end

  it 'sorts alphabetically with boolean directives before value directives' do
    cache_control = Rack::Cache::CacheControl.new('foo=bar, z, x, y, bling=baz, zoom=zib, b, a')
    cache_control.to_s.must_equal 'a, b, x, y, z, bling=baz, foo=bar, zoom=zib'
  end

  it 'responds to #max_age with an integer when max-age directive present' do
    cache_control = Rack::Cache::CacheControl.new('public, max-age=600')
    cache_control.max_age.must_equal 600
  end

  it 'responds to #max_age with nil when no max-age directive present' do
    cache_control = Rack::Cache::CacheControl.new('public')
    cache_control.max_age.must_equal nil
  end

  it 'responds to #shared_max_age with an integer when s-maxage directive present' do
    cache_control = Rack::Cache::CacheControl.new('public, s-maxage=600')
    cache_control.shared_max_age.must_equal 600
  end

  it 'responds to #shared_max_age with nil when no s-maxage directive present' do
    cache_control = Rack::Cache::CacheControl.new('public')
    cache_control.shared_max_age.must_equal nil
  end

  it 'responds to #reverse_max_age with an integer when r-maxage directive present' do
    cache_control = Rack::Cache::CacheControl.new('public, r-maxage=600')
    cache_control.reverse_max_age.must_equal 600
  end

  it 'responds to #reverse_max_age with nil when no r-maxage directive present' do
    cache_control = Rack::Cache::CacheControl.new('public')
    cache_control.reverse_max_age.must_equal nil
  end

  it 'responds to #public? truthfully when public directive present' do
    cache_control = Rack::Cache::CacheControl.new('public')
    assert cache_control.public?
  end

  it 'responds to #public? non-truthfully when no public directive present' do
    cache_control = Rack::Cache::CacheControl.new('private')
    refute cache_control.public?
  end

  it 'responds to #private? truthfully when private directive present' do
    cache_control = Rack::Cache::CacheControl.new('private')
    assert cache_control.private?
  end

  it 'responds to #private? non-truthfully when no private directive present' do
    cache_control = Rack::Cache::CacheControl.new('public')
    refute cache_control.private?
  end

  it 'responds to #no_cache? truthfully when no-cache directive present' do
    cache_control = Rack::Cache::CacheControl.new('no-cache')
    assert cache_control.no_cache?
  end

  it 'responds to #no_cache? non-truthfully when no no-cache directive present' do
    cache_control = Rack::Cache::CacheControl.new('max-age=600')
    refute cache_control.no_cache?
  end

  it 'responds to #must_revalidate? truthfully when must-revalidate directive present' do
    cache_control = Rack::Cache::CacheControl.new('must-revalidate')
    assert cache_control.must_revalidate?
  end

  it 'responds to #must_revalidate? non-truthfully when no must-revalidate directive present' do
    cache_control = Rack::Cache::CacheControl.new('max-age=600')
    refute cache_control.no_cache?
  end

  it 'responds to #proxy_revalidate? truthfully when proxy-revalidate directive present' do
    cache_control = Rack::Cache::CacheControl.new('proxy-revalidate')
    assert cache_control.proxy_revalidate?
  end

  it 'responds to #proxy_revalidate? non-truthfully when no proxy-revalidate directive present' do
    cache_control = Rack::Cache::CacheControl.new('max-age=600')
    refute cache_control.no_cache?
  end
end
