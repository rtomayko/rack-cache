Configuration Language
======================

__Rack::Cache__ includes a configuration system that can be used to specify
fairly sophisticated cache policy on a global or per-request basis.

  - [Synopsis](#synopsis)
  - [Setting Cache Options](#setopt)
  - [Cache Option Reference](#options)
  - [Configuration Machinery - Events and Transitions](#machinery)
  - [Importing Configuration](#import)
  - [Default Configuration Machinery](#default)
  - [Notes](#notes)

<a id='synopsis'></a>

Synopsis
--------

    use Rack::Cache do
      # set cache related options
      set :verbose, true
      set :metastore,   'memcached://localhost:11211'
      set :entitystore, 'file:/var/cache/rack/body'

      # override events / transitions
      on :receive do
        pass! if request.url =~ %r|/dontcache/|
        error! 402 if request.referrer =~ /digg.com/
      end

      on :miss do
        trace 'missed: %s', request.url
      end

      # bring in other configuration machinery
      import 'rack/cache/config/breakers'
      import 'mycacheconfig'
    end

<a id='setopt'></a>

Setting Cache Options
---------------------

Cache options can be set when the __Rack::Cache__ object is created; or by using
the `set` method within a configuration block; or by setting a
`rack-cache.<option>` variable in __Rack__'s __Environment__.

When the __Rack::Cache__ object is instantiated:

    use Rack::Cache,
      :verbose => true,
      :metastore => 'memcached://localhost:11211/',
      :entitystore => 'file:/var/cache/rack'

Using the `set` method within __Rack::Cache__'s configuration context:

    use Rack::Cache do
      set :verbose, true
      set :metastore, 'memcached://localhost:11211/'
      set :entitystore, 'file:/var/cache/rack'
    end

Using __Rack__'s __Environment__:

    env.merge!(
      'rack-cache.verbose' => true,
      'rack-cache.metastore' => 'memcached://localhost:11211/',
      'rack-cache.entitystore' => 'file:/var/cache/rack'
    )

<a id='options'></a>

Cache Option Reference
----------------------

Use the following options to customize __Rack::Cache__:

### `verbose`

Boolean specifying whether verbose trace logging is enabled. This option is
currently enabled (`true`) by default but is likely to be disabled (`false`) in
a future release. All log output is written to the `rack.errors` stream, which
is typically set to `STDERR`.

The `trace`, `info`, `warn`, and `error` methods can be used within the
configuration context to write messages to the errors stream.

### `default_ttl`

An integer specifying the number of seconds a cached object should be considered
"fresh" when no explicit freshness information is provided in a response.
Explicit `Cache-Control` or `Expires` response headers always override this
value. The `default_ttl` option defaults to `0`, meaning responses without
explicit freshness information are considered immediately "stale" and will not
be served from cache without validation.

### `metastore`

A URI specifying the __MetaStore__ implementation used to store request/response
meta information. See the [Rack::Cache Storage Documentation](storage.html)
for detailed information on different storage implementations.

If no metastore is specified, the `heap:/` store is assumed. This implementation
has significant draw-backs so explicit configuration is recommended.

### `entitystore`

A URI specifying the __EntityStore__ implementation used to store
response bodies. See the [Rack::Cache Storage Documentation](storage.html)
for detailed information on different storage implementations.

If no entitystore is specified, the `heap:/` store is assumed. This
implementation has significant draw-backs so explicit configuration is
recommended.

<a id='machinery'></a>

Configuration Machinery - Events and Transitions
------------------------------------------------

The configuration machinery is built around a series of interceptable events and
transitions controlled by a simple configuration language. The following diagram
shows each state (interceptable event) along with their possible transitions:

<p class='center'>
<img src='events.png' alt='Events and Transitions Diagram' />
</p>

Custom logic can be layered onto the `receive`, `hit`, `miss`, `fetch`, `store`,
`deliver`, and `pass` events by passing a block to the `on` method:

    on :fetch do
      trace 'fetched %p from backend application', request.url
    end

Here, the `trace` method writes a message to the `rack.errors` stream when a
response is fetched from the backend application. The `request` object is a
[__Rack::Cache::Request__](./api/classes/Rack/Cache/Request) that can be
inspected (and modified) to determine what action should be taken next.

Event blocks are capable of performing more interesting operations:

  * Transition to a different event or override default caching logic.
  * Modify the request, response, cache entry, or Rack environment options.
  * Set the `metastore` or `entitystore` options to select a different storage
    mechanism / location dynamically.
  * Collect statistics or log request/response/cache information.

When an event is triggered, the blocks associated with the event are executed in
reverse/FILO order (i.e., the block declared last runs first) until a
_transitioning statement_ is encountered. Transitioning statements are suffixed
with a bang character (e.g, `pass!`, `store!`, `error!`) and cause the current
event to halt and the machine to transition to the subsequent event; control is
not returned to the original event. The [default configuration](#default)
includes documentation on available transitions for each event.

The `next` statement can be used to exit an event block without transitioning
to another event. Subsequent event blocks are executed until a transitioning
statement is encountered:

    on :fetch do
      next if response.freshness_information?

      if request.url =~ /\/feed$/
        trace 'feed will expire in fifteen minutes'
        response.ttl = 15 * 60
      end
    end

<a id='import'></a>

Importing Configuration
-----------------------

Since caching logic can be layered, it's possible to separate various bits of
cache policy into files for organization and reuse.

    use Rack::Cache do
      import 'rack/cache/config/busters'
      import 'mycacheconfig'

      # more stuff here
    end

The `breakers` and `mycacheconfig` configuration files are normal Ruby source
files (i.e., they have a `.rb` extension) situated on the `$LOAD_PATH` - the
`import` statement works like Ruby's `require` statement but the contents of the
files are evaluated in the context of the configuration machinery, as if
specified directly in the configuration block.

The `rack/cache/config/busters.rb` file makes a good example. It hooks into the
`fetch` event and adds an impractically long expiration lifetime to any response
that includes a cache busting query string:

<%= File.read('lib/rack/cache/config/busters.rb').gsub(/^/, '    ') %>


<a id='default'></a>

Default Configuration Machinery
-------------------------------

The `rack/cache/config/default.rb` file is imported when the __Rack::Cache__
object is instantiated and before any custom configuration code is executed.
It's useful to understand this configuration because it drives the default
transitioning logic.

<%= File.read('lib/rack/cache/config/default.rb').gsub(/^/, '    ') %>

<a id='notes'></a>

Notes
-----

The configuration language was inspired by [Varnish][var]'s
[VCL configuration language][vcl].

[var]: http://varnish.projects.linpro.no/
  "Varnish HTTP accelerator"

[vcl]: http://tomayko.com/man/vcl
  "VCL(7) -- Varnish Configuration Language Manual Page"
