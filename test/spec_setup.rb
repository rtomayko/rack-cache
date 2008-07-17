begin
  require 'test/spec'
rescue LoadError => boom
  require 'rubygems' rescue nil
  require 'test/spec'
end

begin
  require 'rack/cache'
rescue LoadError => boom
  $:.unshift File.join(File.dirname(File.dirname(__FILE__)), 'lib')
  require 'rack/cache'
end

