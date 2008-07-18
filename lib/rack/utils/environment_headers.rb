require 'rack/utils'

module Rack::Utils

  class EnvironmentHeaders
    include Enumerable

    def initialize(env)
      @env = env
    end

    def [](header_name)
      @env[env_name(header_name)]
    end

    def []=(header_name, value)
      @env[env_name(header_name)] = value
    end

    def include?(header_name)
      @env.include?(env_name(header_name))
    end

    def keys
      @env.keys.map { |env_name| header_name(env_name) }
    end

    def each
      @env.each { |env_name,value| yield header_name(env_name), value }
    end

    def delete(header_name)
      @env.delete(env_name(header_name))
    end

    def to_env
      @env
    end

    alias_method :to_hash, :to_env

  private

    def env_name(header_name)
      'HTTP_' + header_name.upcase.gsub('-', '_')
    end

    def header_name(env_name)
      env_name.
        sub(/^HTTP_/, '').
        downcase.
        capitalize.
        gsub(/(.)_/) { $1.upcase + '-' }
    end

    def method_missing(method_name, *args, &block)
      @env.send(method_name, *args, &block)
    end

  end

end
