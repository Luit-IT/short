# URL Shortener in Go, Redis and Varnish

This URL shortener is a personal project to have an URL shortener that runs
with the stuff I already have.  The interface to the shortener is a Go
program, with either a web- or command-line interface (to be determined).  The
links are to be handled by Varnish by connecting to Redis, where the data is
stored, by the VCL to determine where to redirect to.


## Redis storage format

The URLs are hashed and encoded to yield a URL-safe identifier.  For this
system SHA1 and URL-safe base64 (with hyphen and underscore) are used.  The
first two characters are used as key in Redis, and the second pair as the
minimal hash key.  This will give you a maximum of 4096 hashes each containing
keys with a minimal length of 2 characters.  To store a new URL, its
identifier is sliced to a minimal unique identifier;  the identifiers already
stored in the system that start with the same characters make the new unique
identifier longer.  This way even hash collisions are unlikely to cause
problems.  The values stored within the hashes are the URLs for each
identifier.

Configuration allows setting the database number and key prefix used.  

This setup also allows, with support of the application that has to store the
URLs, short URLs to represent something human-readable, e.g.
`example.com/ShortURL`, with the unique identifier being fixed to `ShortURL`. 


## Lookup

The lookup phase will happen when the VCL detects a URL that has the right
format. For example, varnish matches `req.url ~ "/l/[A-Za-z0-9\-_]{4,}"`. 


## TODO

Everything!
