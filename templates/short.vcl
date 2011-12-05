import redis;

backend self {
	.host = "127.0.0.1";
	.port = "80";
}

sub vcl_recv {
	if (req.url ~ "(?i)^/l/") {
		set req.backend = self;
		if (req.url ~ "(?i)^/l/r/") {
			// Looks like a cache miss, and successful lookup, return a redirect now
			// (should check for localhost origin?)
			error 666 regsub(req.url, "(?i)^/l/r/([\d\D]*)$", "\1");
		}
	}
}

sub vcl_error {
	if (obj.status == 666) {
		// Returning a redirect, so the self-generated response can be cached
		set obj.status = 302;
		set obj.http.Location = obj.response;
		set obj.response = "Found";
		return (deliver);
	}
}

sub vcl_miss {
	if (req.url ~ "(?i)^/l/") {
		// First try and make this URL into a Redis lookup command
		set req.http.Redis-Command = regsub(req.url,
			"^(?i)^/l/([a-z0-9\-_]{2})([a-z0-9\-_]{2,30}=?=?)$",
			"HGET short:\1 \2");
		if (req.url == req.http.Redis-Command) {
			// Looks like the url doesn't match the pattern, so it's 404 Not Found
			unset req.http.Redis-Command;
			error 404 "Not Found";
		}

		// Issue the Redis command
		set bereq.url = redis.call(req.http.Redis-Command);
		unset req.http.Redis-Command;
		if (bereq.url) {
			// It returned something useful, use it!
			set bereq.url = "/l/r/" + bereq.url;
			return (fetch);
		}
		// Redis didn't return what we were looking for, so it's 404 Not Found
		error 404 "Not Found";
	}
}
