## 1.1 / September 2011

  * Allow (INM/IMS) validation requests through to backend on miss. Makes it
    possible to use validation for private / uncacheable responses. A number of
    people using Rails's stale?() helper reported that their validation logic was
    never kicking in.

  * Add rack env rack-cache.force-pass option to bypass rack-cache on
    per request basis

  * Fix an issue with memcache namespace not being set when using the
    :namespace option instead of :prefix_key.

  * Fix test failures due to MockResponse changes in recent Rack
    version (issue #34)

## 1.0.3 / August 2011

  * Fix bug passing options to memcached and dalli

  * Document cache_key

## 1.0.1 / April 2011

  * Added lib/rack-cache.rb to match package name for auto-requiring machinery.

  * Fixed a number of issues caused by Rack::Cache not closing the body received
    from the application. Rack::Lock and other middleware use body.close to
    signal the true end of request processing so failure to call this method
    can result in strange issues (e.g.,
    "ThreadError: deadlock; recursive locking")

  * Fixed a bug where Rack::Cache would blow up writing the rack env to the meta
    store when the env contained an all uppercase key whose value wasn't
    marshalable. Passenger and some other stuff write such keys apparently.

  * The test suite has moved from test-spec to bacon. This is a short term
    solution to the problem of not being able to run tests under Ruby 1.9.x.
    The test suite will be moved to basic Test::Unit style sometime in the
    future.

## 1.0 / December 2010

  * Rack::Cache is 1.0 and will now maintain semantic versioning <http://semver.org/>

  * Add Dalli memcache client support and removed support for the unmaintained
    memcache-client library. You will need to move your apps to Dalli before
    upgrading rack-cache to 1.0.

## 0.5.3 / September 2010

  * A matching If-Modified-Since is ignored if an If-None-Match is also provided
    and doesn't match. This is in line with RFC 2616.

  * Converts string status codes to integers before returns to workaround bad
    behaving rack middleware and apps.

  * Misc doc clean up.

## 0.5.2 / September 2009

  * Exceptions raised from the metastore are not fatal. This makes a lot of
    sense in most cases because its okay for the cache to be down - it
    shouldn't blow up your app.

## 0.5.1 / June 2009

  * Added support for memcached clusters and other advanced
    configuration provided by the memcache-client and memcached
    libraries. The "metastore" and "entitystore" options can now be
    set to a MemCache object or Memcached object:

    memcache = MemCache.new(['127.1.1.1', '127.1.1.2'], :namespace => "/foo")
    use Rack::Cache,
      :metastore => memcache,
      :entitystore => memcache

  * Fix "memcached://" metastore URL handling. The "memcached" variation
    blew up, the "memcache" version was fine.

## 0.5.0 / May 2009

  * Added meta and entity store implementations based on the
    memcache-client library. These are the default unless the memcached
    library has already been required.

  * The "allow_reload" and "allow_revalidate" options now default to
    false instead of true. This means we break with RFC 2616 out of
    the box but this is the expected configuration in a huge majority
    of gateway cache scenarios. See the docs on configuration
    options for more information on these options:
    http://tomayko.com/src/rack-cache/configuration

  * Added Google AppEngine memcache entity store and metastore
    implementations. To use GAE's memcache with rack-cache, set the
    "metastore" and "entitystore" options as follows:

        use Rack::Cache,
          :metastore   => 'gae://cache-meta',
          :entitystore => 'gae://cache-body'

    The 'cache-meta' and 'cache-body' parts are memcache namespace
    prefixes and should be set to different values.

## 0.4.0 / March 2009

  * Ruby 1.9.1 / Rack 1.0 compatible.

  * Invalidate cache entries that match the request URL on non-GET/HEAD
    requests. i.e., POST, PUT, DELETE cause matching cache entries to
    be invalidated. The cache entry is validated with the backend using
    a conditional GET the next time it's requested.

  * Implement "Cache-Control: max-age=N" request directive by forcing
    validation when the max-age provided exceeds the age of the cache
    entry. This can be disabled by setting the "allow_revalidate" option to
    false.

  * Properly implement "Cache-Control: no-cache" request directive by
    performing a full reload. RFC 2616 states that when "no-cache" is
    present in the request, the cache MUST NOT serve a stored response even
    after successful validation. This is slightly different from the
    "no-cache" directive in responses, which indicates that the cache must
    first validate its entry with the origin. Previously, we implemented
    "no-cache" on requests by passing so no new cache entry would be stored
    based on the response. Now we treat it as a forced miss and enter the
    response into the cache if it's cacheable. This can be disabled by
    setting the "allow_reload" option to false.

  * Assume identical semantics for the "Pragma: no-cache" request header
    as the "Cache-Control: no-cache" directive described above.

  * Less crazy logging. When the verbose option is set, a single log entry
    is written with a comma separated list of trace events. For example, if
    the cache was stale but validated, the following log entry would be
    written: "cache: stale, valid, store". When the verbose option is false,
    no logging occurs.

  * Added "X-Rack-Cache" response header with the same comma separated trace
    value as described above. This gives some visibility into how the cache
    processed the request.

  * Add support for canonicalized cache keys, as well as custom cache key
    generators, which are specified in the options as :cache_key as either
    any object that has a call() or as a block. Cache key generators get
    passed a request object and return a cache key string.

## 0.3.0 / December 2008

  * Add support for public and private cache control directives. Responses
    marked as explicitly public are cached even when the request includes
    an Authorization or Cookie header. Responses marked as explicitly private
    are considered uncacheable.

  * Added a "private_headers" option that dictates which request headers
    trigger default "private" cache control processing. By default, the
    Cookie and Authorization headers are included. Headers may be added or
    removed as necessary to change the default private logic.

  * Adhere to must-revalidate/proxy-revalidate cache control directives by
    not assigning the default_ttl to responses that don't include freshness
    information. This should let us begin using default_ttl more liberally
    since we can control it using the must-revalidate/proxy-revalidate directives.

  * Use the s-maxage Cache-Control value in preference to max-age when
    present. The ttl= method now sets the s-maxage value instead of max-age.
    Code that used ttl= to control freshness at the client needs to change
    to set the max-age directive explicitly.

  * Enable support for X-Sendfile middleware by responding to #to_path on
    bodies served from disk storage. Adding the Rack::Sendfile component
    upstream from Rack::Cache will result in cached bodies being served
    directly by the web server (instead of being read in Ruby).

  * BUG: MetaStore hits but EntityStore misses. This would 500 previously; now
    we detect it and act as if the MetaStore missed as well.

  * Implement low level #purge method on all concrete entity store
    classes -- removes the entity body corresponding to the SHA1 key
    provided and returns nil.

  * Basically sane handling of HEAD requests. A HEAD request is never passed
    through to the backend except when transitioning with pass!. This means
    that the cache responds to HEAD requests without invoking the backend at
    all when the cached entry is fresh. When no cache entry exists, or the
    cached entry is stale and can be validated, the backend is invoked with
    a GET request and the HEAD is handled right before the response
    is delivered upstream.

  * BUG: The Age response header was not being set properly when a stale
    entry was validated. This would result in Age values that exceeded
    the freshness lifetime in responses.

  * BUG: A cached entry in a heap meta store could be unintentionally
    modified by request processing since the cached objects were being
    returned directly. The result was typically missing/incorrect header
    values (e.g., missing Content-Type header). [dkubb]

  * BUG: 304 responses should not include entity headers (especially
    Content-Length). This is causing Safari/WebKit weirdness on 304
    responses.

  * BUG: The If-None-Match header was being ignored, causing the cache
    to send 200 responses to matching conditional GET requests.

## 0.2.0 / 2008-10-24 / Initial Release

  * Document events and transitions in `rack/cache/config/default.rb`
  * Basic logging support (`trace`, `warn`, `info`, `error` from within Context)
  * EntityStore: store entity bodies keyed by SHA
  * MetaStore: store response headers keyed by URL
  * Last-Modified/ETag validation
  * Vary support
  * Implement error! transition
  * New Rack::Cache::Core
  * memcached meta and entity store implementations
  * URI based storage configuration
  * Read options from Rack env if present (rack-cache.XXX keys)
  * `object` is now `entry`
  * Documentation framework and website
  * Document storage areas and implementations
  * Document configuration/events

## 0.1.0 / 2008-07-21 / Proof of concept (unreleased)

  * Basic core with event support
  * `#import` method for bringing in config files
  * Freshness based expiration
  * RFC 2616 If-Modified-Since based validation
  * A horribly shitty storage back-end (Hash in mem)
  * Don't cache hop-by-hop headers: Connection, Keep-Alive, Proxy-Authenticate,
    Proxy-Authorization, TE, Trailers, Transfer-Encoding, Upgrade
