Configuration
=============

__Rack::Cache__ includes a configuration system (inspired by [Varnish][var]'s
[VCL configuration language][vcl]) that can be used to specify fairly
sophisticated cache policy on a global or per-request basis.

[var]: http://varnish.projects.linpro.no/
  "Varnish HTTP accelerator"

[vcl]: http://tomayko.com/man/vcl
  "VCL(7) -- Varnish Configuration Language Manual Page"

Synopsis
--------

    use Rack::Cache do
      # set cache related options
      set :verbose, true
      set :metastore,   'file:/var/cache/rack/meta'
      set :entitystore, 'file:/var/cache/rack/body'

      # define event handlers
      on :receive do
        pass! if request.url =~ %r|/uncacheable/|
        error! 402 if request.referrer =~ /digg.com/
      end
      on :miss do
        trace 'missed: %s', request.url
      end

      # bring in other configuration files
      import 'rack/cache/config/breakers'
      import 'mycacheconfig'
    end

Cache Options
-------------

The following

### `rack-cache.verbose`

Enable verbose trace logging. This option is currently enabled by
default but is likely to be disabled in a future release.

### `rack-cache.default_ttl`

The number of seconds that a cached object should be considered "fresh" when no
explicit freshness information is provided in a response. Explicit
`Cache-Control` or `Expires` header present in a response always override
this value.

Default: 0

### `rack-cache.metastore`

A URI specifying the metastore implementation used to store request/response
meta information. See the [Rack::Cache Storage Documentation](storage.html)
for detailed information on different storage implementations.

If no metastore is specified the 'heap:/' store is assumed. This implementation
has significant draw-backs so explicit configuration is recommended.

### `rack-cache.entitystore`

A URI specifying the entity-store implementation used to store
response bodies. See the [Rack::Cache Storage Documentation](storage.html)
for detailed information on different storage implementations.

If no entitystore is specified the 'heap:/' store is assumed. This
implementation has significant draw-backs so explicit configuration is
recommended.

Events and Transitions
----------------------

The configuration language is built around a series of interceptable events and
transitions controlled by a simple configuration language.

Some statements are considered _transitioning_ in that they cause the current
event to halt processing. In the example above, both the `pass!` and `error!`
statements cause the `:receive` event to halt (the block is immediately exited
via `throw`), which causes the machine to begin transitioning to the subsequent
event.

Caching policy can be layered. Event handlers are executed in last-on/first-off
(LOFO) order until a transitioning statement is executed.

Importing
---------

This allows small bits of cache policy to be captured in separate files and
combined as needed:

    use Rack::Cache do
      import 'rack/cache/config/accelerator'
      import 'rack/cache/config/breakers'
    end

The `breakers` and `accelerator` configuration files are normal Ruby source
files (i.e., with a ".rb" extension) on the `$LOAD_PATH`; `import` evaluates
their contents in the context of the configuration machinery as if their
contents were specified directly in the initialization block.

Default Configuration
---------------------

The `rack/cache/config/default.rb` file is imported before any custom
configuration code is executed. Any custom event handlers defined in your
application are executed before the default event handlers.

<%= File.read('doc/config/default.rb.html') %>
