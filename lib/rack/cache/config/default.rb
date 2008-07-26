# Forward the request to the backend and call finish to send the
# response back upstream.
on :pass do
  debug 'pass request to backend'
  @backend_request = @request
  @backend_response = Response.new(*@backend.call(@request.env))
  @response = @backend_response
  finish
end

# Called when the request is initially received.
on :receive do
  debug 'receive request'
  # pass if request.header['Cache-Control'] =~ /no-cache/
  pass unless request.method? 'GET', 'HEAD'
  pass if request.header? 'Cookie', 'Authorization', 'Expect'
  lookup
end

# Attempt to lookup the request in the cache. If a potential
# response is found, control transfers to the hit event with
# @object set to response object retrieved from cache. When
# no object is found in the cache, control transfers to miss.
on :lookup do
  debug 'lookup in cache'
  if object = @storage.get(request.fullpath)
    @object = Response.activate(object)
    if @object.fresh?
      hit
    else
      validate
    end
  end
  miss
end

# The cache hit after a lookup.
on :hit do
  debug 'cache hit'
  @response = @object
  deliver
end

# The cache hit but the cached entity is no longer fresh, or
# the request requires validation for some other reason.
on :validate do
  debug 'cached object found, but stale - validating w/ origin'

  # TODO extract code that builds request to forward
  environment = @request.env.dup
  environment.delete('HTTP_IF_MODIFIED_SINCE')
  environment.delete('HTTP_IF_NONE_MATCH')
  @backend_request = Request.new(environment)

  # add validators to the backend request
  if last_modified = @object['Last-Modified']
    @backend_request.headers['If-Modified-Since'] = last_modified
  end
  if etag = @object['ETag']
    @backend_request.headers['If-None-Match'] = etag
  end

  # fetch the response from the backend
  @backend_response = Response.new(*@backend.call(@backend_request.env))

  # if we're just revalidating, merge headers, update the cache
  # and hit.
  if @backend_response.status == 304    # TODO 412 responses
    debug "cached object up-to-date w/ backend"
    @response = @object
    # Merge headers
    %w[Date Expires Cache-Control Etag Last-Modified].each do |hd|
      next unless @backend_response.headers.key?(hd)
      @response.headers[hd] = @backend_response.headers[hd]
    end
    @response.headers.delete('Age')
    @object = @response
    store
  elsif @backend_response.cacheable?
    debug "cached object refreshed"
    @response = @backend_response.dup
    store
  else
    debug "cached object is no longer cacheable ..."
    @response = @backend_response
    deliver
  end
end

# Nothing was found in the cache.
on :miss do
  debug 'cache miss'
  # TODO extract code that builds request to forward
  environment = @request.env.dup
  environment.delete('HTTP_IF_MODIFIED_SINCE')
  @backend_request = Request.new(environment)
  fetch
end

# Fetch the response from the backend and transfer control
# to the store event.
on :fetch do
  debug 'fetch from backend'
  @backend_response = Response.new(*@backend.call(@backend_request.env))
  if @backend_response.cacheable?
    debug "response is cacheable ..."
    @response = @backend_response.dup
    store
  else
    debug "response isn't cacheable ..."
    @response = @backend_response
    deliver
  end
end

# Store the response in the cache and transfer control to
# the deliver event.
on :store do
  @object = @response.cache
  @object.ttl = default_ttl if @object.ttl.nil?
  debug 'store backend response in cache (TTL: %ds)', @object.ttl
  @storage.put(@request.fullpath, object.to_a)
  @response = @object
  deliver
end

on :deliver do
  # Handle conditional GET w/ If-Modified-Since
  if @response.last_modified_at?(@request.header['If-Modified-Since'])
    debug 'upstream version is unmodified; sending 304'
    response.status = 304
    response.body = ''
  end
  debug 'deliver response'
  finish
end


# Complete processing of the request. The backend_request,
# backend_response, and response objects should all be available
# when this event is invoked.
on :finish do
  throw :finish, @response.to_a
end
