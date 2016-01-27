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

http://rtomayko.github.com/rack-cache/

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
  :metastore   => 'file:/var/cache/rack/meta',
  :entitystore => 'file:/var/cache/rack/body',
  :verbose     => true

run app
```

Assuming you've designed your backend application to take advantage of HTTP's
caching features, no further code or configuration is required for basic
caching.

Using with Rails
----------------

Add this to your `config/environment.rb`:

```Ruby
config.middleware.use Rack::Cache,
   :verbose => true,
   :metastore   => 'file:/var/cache/rack/meta',
   :entitystore => 'file:/var/cache/rack/body'
```

You should now see `Rack::Cache` listed in the middleware pipeline:

    rake middleware

See the following for more information:

    http://snippets.aktagon.com/snippets/302-how-to-setup-and-use-rack-cache-with-rails

Using with Dalli
----------------

Dalli is a high performance memcached client for Ruby.
More information at: https://github.com/mperham/dalli

```Ruby
require 'dalli'
require 'rack/cache'

use Rack::Cache,
  :verbose => true,
  :metastore   => "memcached://localhost:11211/meta",
  :entitystore => "memcached://localhost:11211/body"

run app
```

Using the Noop backend for the entity store
-------------------------------------------

The Noop backend can be used for the entity store if you're not interested in the bodies of cached 
responses. This backend does not actually persist response bodies, so no memory or disk space has 
to be allocated for them (the metastore backend still needs those resources). 

Be careful: when using this backend, responses retrieved from the cache always have an empty body. You must 
check if the response comes from the cache (by looking at the presence of 'fresh' or 'valid' in the 
```X-Rack-Cache``` HTTP header) and in this case you should ignore the response body.
 
There are two ways of configuring rack-cache to use this backend:
 
```Ruby
require 'rack/cache'

use Rack::Cache,
 :verbose => true,
 :metastore   => "file:/var/cache/rack/meta", # you can use any backend here
 :entitystore => nil

run app
```

or

```Ruby
require 'rack/cache'

use Rack::Cache,
 :verbose => true,
 :metastore   => "file:/var/cache/rack/meta", # you can use any backend here
 :entitystore => "noop://"

run app
```

License: MIT<br/>
[![Build Status](https://travis-ci.org/rtomayko/rack-cache.png)](https://travis-ci.org/rtomayko/rack-cache)

