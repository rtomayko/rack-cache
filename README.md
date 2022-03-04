# Moved to https://github.com/rack/rack-cache

Rack::Cache
===========

Rack::Cache is suitable as a quick drop-in component to enable HTTP caching for
Rack-based applications that produce freshness (Expires, Cache-Control) and/or
validation (Last-Modified, ETag) information:

  * Standards-based (RFC 2616)
  * Freshness/expiration based caching
  * Validation (If-Modified-Since / If-None-Match)
  * Vary support
  * Cache-Control: public, private, max-age, s-maxage, must-revalidate,
    and proxy-revalidate.
  * Portable: 100% Ruby / works with any Rack-enabled framework
  * Disk, memcached, and heap memory storage backends

For more information about Rack::Cache features and usage, see:

https://rtomayko.github.com/rack-cache/

Rack::Cache is not overly optimized for performance. The main goal of the
project is to provide a portable, easy-to-configure, and standards-based
caching solution for small to medium sized deployments. More sophisticated /
high-performance caching systems (e.g., Varnish, Squid, httpd/mod-cache) may be
more appropriate for large deployments with significant throughput requirements.

Installation
------------

    gem install rack-cache

Basic Usage
-----------

`Rack::Cache` is implemented as a piece of Rack middleware and can be used with
any Rack-based application. If your application includes a rackup (`.ru`) file
or uses Rack::Builder to construct the application pipeline, simply require
and use as follows:

```Ruby
require 'rack/cache'

use Rack::Cache,
  metastore:    'file:/var/cache/rack/meta',
  entitystore:  'file:/var/cache/rack/body',
  verbose:      true

run app
```

Assuming you've designed your backend application to take advantage of HTTP's
caching features, no further code or configuration is required for basic
caching.

Using with Rails
----------------

```Ruby
# config/application.rb
config.action_dispatch.rack_cache = true
# or
config.action_dispatch.rack_cache = {
   verbose:     true,
   metastore:   'file:/var/cache/rack/meta',
   entitystore: 'file:/var/cache/rack/body'
}
```

You should now see `Rack::Cache` listed in the middleware pipeline:

    rake middleware

[more information](https://snippets.aktagon.com/snippets/302-how-to-setup-and-use-rack-cache-with-rails)

Using with Dalli
----------------

Dalli is a high performance memcached client for Ruby.
More information at: https://github.com/mperham/dalli

```Ruby
require 'dalli'
require 'rack/cache'

use Rack::Cache,
  verbose:  true,
  metastore:    "memcached://localhost:11211/meta",
  entitystore:  "memcached://localhost:11211/body"

run app
```

Noop entity store
-----------------

Does not persist response bodies (no disk/memory used).<br/>
Responses from the cache will have an empty body.<br/>
Clients must ignore these empty cached response (check for X-Rack-Cache response header).<br/>
Atm cannot handle streamed responses, patch needed.

```Ruby
require 'rack/cache'

use Rack::Cache,
 verbose: true,
 metastore: <any backend>
 entitystore: "noop:/"

run app
```

Ignoring tracking parameters in cache keys
-----------------

It's fairly common to include tracking parameters which don't affect the content
of the page. Since Rack::Cache uses the full URL as part of the cache key, this
can cause unneeded churn in your cache. If you're using the default key class
`Rack::Cache::Key`, you can configure a proc to ignore certain keys/values like
so:

```Ruby
Rack::Cache::Key.query_string_ignore = proc { |k, v| k =~ /^(trk|utm)_/ }
```

License: MIT<br/>
[![Build Status](https://travis-ci.org/rtomayko/rack-cache.svg)](https://travis-ci.org/rtomayko/rack-cache)
