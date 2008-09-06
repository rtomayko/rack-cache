Rack::Cache
===========

We strive to implement those portions of [RFC 2616][rfc] / [Section 13][s13]
relevant to gateway (i.e., "reverse proxy") cache scenarios with a
system for specifying cache policy. Rack::Cache is suitable as a quick,
drop-in component to enable caching for [Rack][]-enabled applications that
provide freshness (`Expires`, `Cache-Control`) and/or validation
(`Last-Modified`, `ETag`) information.

  * Standards-based (RFC 2616 compliance)
  * Freshness/expiration based caching and validation
  * Supports Vary
  * Portable: 100% Ruby / works with any Rack-enabled framework
  * VCL-like configuration language for advanced caching policies
  * Disk, memcached, sqlite3, and memory storage backends

Rack::Cache is not overly optimized for performance. The main goal of the
project is to provide a portable, easy-to-configure, and standards-based
caching solution for small to medium sized deployments. More sophisticated /
performant caching systems (e.g., Varnish, Squid, httpd/mod-cache) may be
more appropriate for large deployments with crazy throughput requirements.

[rfc]: http://tools.ietf.org/html/rfc2616
  "RFC 2616 - Hypertext Transfer Protocol -- HTTP/1.1 [ietf.org]"

[s13]: http://tools.ietf.org/html/rfc2616#section-13
  "RFC 2616 / Section 13 Caching in HTTP"

[rack]: http://rack.rubyforge.org/
  "Rack: a Ruby Webserver Interface"

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

Rack::Cache is implemented as a piece of [Rack][] middleware and can be used
with any Rack-based application. If your application includes a rackup
(`.ru`) file or uses Rack::Builder to construct the application pipeline,
simply `require` and `use` as follows:

    require 'rack/cache'
    use Rack::Cache do
      # ... cache configuration ...
      set :verbose, true
    end

    run foo_app

Configuration
-------------

Rack::Cache includes a configuration system (inspired by [Varnish][var]'s
[VCL configuration language][vcl]) that can be used to specify fairly
complicated cache policy. The system is built around a series of
interceptable events and transitions that can be controlled through
a simple configuration language.

    use Rack::Cache do
      on :receive do
        pass if request.url =~ %r|/uncacheable/|
        error 402 if request.referrer =~ /digg.com/
      end
      on :miss do
        trace 'missed: %s', request.url
      end
    end

Some statements are considered _transitioning_, in that they cause the
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

The `breakers` and `accelerator` configuration files are normal Ruby source
files (i.e., with a ".rb" extension) on the `$LOAD_PATH`; `import` evaluates
their contents in the context of the configuration machinery as if their
contents were specified directly in the initialization block.

[var]: http://varnish.projects.linpro.no/
  "Varnish HTTP accelerator"

[vcl]: http://tomayko.com/man/vcl
  "VCL(7) -- Varnish Configuration Language Manual Page"

See Also
--------

The overall design of Rack::Cache is based almost entirely on the work of
the internet standards community. The following resources provide a good
starting point for exploring the concepts we've built on:

  * [RFC 2616](http://www.ietf.org/rfc/rfc2616.txt), especially
    [Section 13, "Caching in HTTP"](http://www.w3.org/Protocols/rfc2616/rfc2616-sec13.html)

  * Mark Nottingham's [Caching Tutorial](http://www.mnot.net/cache_docs/),
    especially the short section on
    [How Web Caches Work](http://www.mnot.net/cache_docs/#WORK)

  * Joe Gregorio's [Doing HTTP Caching Right](http://www.xml.com/lpt/a/1642)

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
