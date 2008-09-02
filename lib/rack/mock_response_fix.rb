require 'rack/mock'

module Rack

  class MockResponse

    def initialize_with_body_closing(status, headers, body, errors=StringIO.new(""), &b)
      def body.each_with_auto_close(&block)
        r = each_without_auto_close(&block)
        close if respond_to? :close
        r
      end
      mc = (class<<body;self;end)
      mc.send :alias_method, :each_without_auto_close, :each
      mc.send :alias_method, :each, :each_with_auto_close
      initialize_without_body_closing(status, headers, body, errors, &b)
    end

    alias_method :initialize_without_body_closing, :initialize
    alias_method :initialize, :initialize_with_body_closing

  end

end
