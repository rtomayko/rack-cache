# Called at the beginning of request processing, after the complete
# request has been fully received. Its purpose is to decide whether or
# not to serve the request and how to do it.
#
# The request should not be modified.
#
# Possible transitions from receive:
#
#   * pass! - pass the request to the backend the response upstream,
#     bypassing all caching features.
#
#   * lookup! - attempt to locate the entry in the cache. Control will
#     pass to the +hit+, +miss+, or +fetch+ event based on the result of
#     the cache lookup.
#
#   * error! - return the error code specified, abandoning the request.
#
on :receive do
  pass! unless request.method? 'GET', 'HEAD'
  pass! if request.header? 'Cookie', 'Authorization', 'Expect'
  lookup!
end

# Called upon entering pass mode. The request is sent to the backend,
# and the backend's response is sent to the client, but is not entered
# into the cache. The event is triggered immediately after the response
# is received from the backend but before the it has been sent upstream.
#
# Possible transitions from pass:
#
#   * finish! - deliver the response upstream.
#
#   * error! - return the error code specified, abandoning the request.
#
on :pass do
  finish!
end

# Called after a cache lookup when no matching entry is found in the
# cache. Its purpose is to decide whether or not to attempt to retrieve
# the response from the backend and in what manner.
#
# Possible transitions from miss:
#
#   * fetch! - retrieve the requested document from the backend with
#     caching features enabled.
#
#   * pass! - pass the request to the backend and the response upstream,
#     bypassing all caching features.
#
#   * error! - return the error code specified and abandon request.
#
# The default configuration transfers control to the fetch event.
on :miss do
  fetch!
end

# Called after a cache lookup when the requested document is found in
# the cache and is fresh.
#
# Possible transitions from hit:
#
#   * deliver! - transfer control to the deliver event, sending the cached
#     response upstream.
#
#   * pass! - abandon the cache entry and transfer to pass mode. The
#     original request is sent to the backend and the response sent
#     upstream, bypassing all caching features.
#
#   * error! - return the error code specified and abandon request.
#
on :hit do
  deliver!
end

# Called after a document is successfully retrieved from the backend
# application or after a cache entry is validated with the backend.
# During validation, the original request is used as a template for a
# conditional GET request with the backend. The +original_response+
# object contains the response as received from the backend and +entry+
# is set to the cached response that triggered validation.
#
# Possible transitions from fetch:
#
#   * store! - store the fetched response in the cache or, when
#     validating, update the cached response with validated results.
#
#   * deliver! - deliver the response upstream without entering it
#     into the cache.
#
#   * error! return the error code specified and abandon request.
#
on :fetch do
  store! if response.cacheable?
  deliver!
end

# Called immediately before an entry is written to the underlying
# cache. The +entry+ object may be modified.
#
# Possible transitions from store:
#
#   * persist! - commit the object to cache and transfer control to
#     the deliver event.
#
#   * deliver! - transfer control to the deliver event without committing
#     the object to cache.
#
#   * error! - return the error code specified and abandon request.
#
on :store do
  trace 'store backend response in cache (ttl: %ds)', entry.ttl
  persist!
end

# Called immediately before +response+ is delivered upstream. +response+
# may be modified at this point but the changes will not effect the
# cache since the entry has already been persisted.
#
#   * finish! - complete processing and send the response upstream
#
#   * error! - return the error code specified and abandon request.
#
on :deliver do
  finish!
end

# Called when an error! transition is triggered. The +response+ has the
# error code, headers, and body that will be delivered to upstream and
# may be modified if needed.
on :error do
  finish!
end
