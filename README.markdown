Rack::Cache
===========

Caching middleware for Rack.

We strive to implement the portions of [RFC 2616][2616] relevant to
reverse proxy cache scenarios with a robust system for specifying
cache policy. Rack::Cache is suitable as a quick, drop-in component to
enable caching for Rack-enabled applications that provide freshness
(Expires, Cache-Control/max-age) and/or validation (Last-Modified,
Etag) information.

Rack::Cache is not overly optimized for performance. The main goal of
the project is to provide a portable and easy-to-configure caching
solution for small to medium deployments. More sophisticated caching
systems (e.g., Varnish, Squid, httpd/mod_cache) are appropriate for
larger deployments.

[2616]: http://www.ietf.org/rfc/rfc2616.txt
  "Request for Comments: 2616 [ietf.org]"

Status
------

Rack::Cache is a young and experimental project that is likely to
change substantially and may not be wholly functional, consistent,
fast, or correct.

Installation
------------

From Gem:

    $ sudo gem install rack-cache

With a local working copy:

    $ git clone git://github.com/rtomayko/rack-cache.git
    $ rake package && sudo rake install

Basic Usage
-----------

The Rack::Cache module is typically used as a piece of Rack middleware
(e.g., in a rackup file). To use the default (conservative)
configuration, simply `require` and `use`:

    require 'rack/cache'
    use Rack::Cache

Configuration
-------------

Rack::Cache has a configuration system (inspired by Varnish's VCL
configuration language) that can be used to specify fairly complicated
cache policy. The system is built around a series of interceptable
events and transitions that can be controlled through configuration.

    use Rack::Cache do
      on :receive do
        pass if request.url =~ %r|/uncacheable/|
        error 402 if request.referrer =~ /digg.com/
      end
      on :miss do
        trace 'missed: %s', request.url
      end
    end

Some statements are considered "transitioning", in that they cause the
current event to halt processing. In the example above, both the
`pass` and `error` statements cause the `:receive` event to halt (the
block is immediately exited via `throw`), which causes the machine to
begin transitioning to the subsequent event.

Caching policy can be layered. Event handlers are executed in
last-on/first-off (LOFO) order until a transitioning statement is
made. This allows small bits of cache policy to be captured in
separate files and combined as needed:

    use Rack::Cache do
      import 'rack/cache/config/accelerator'
      import 'rack/cache/config/breakers'
    end

The `breakers` and `accelerator` configuration files are normal Ruby
source files on the `$LOAD_PATH`; `import` evaluates their contents in
the context of the configuration machinery (as if their contents were
specified directly in the initialization block.

License
-------

Copyright (c) 2008 Ryan Tomayko <http://tomayko.com/>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to
deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER 
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
