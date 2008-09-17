# The default configuration ignores the `Cache-Control: no-cache` directive on
# requests. Per RFC 2616, the presence of the no-cache directive should cause
# intermediaries to process requests as if no cached version were available.
# However, this directive is most often targetted at shared proxy caches, not
# gateway caches, and so we've chosen to break with the spec in our default
# configuration.
#
# Import 'rack/cache/config/no-cache' to enable standards-based
# processing.

on :receive do
  pass! if request.header['Cache-Control'] =~ /no-cache/
end
