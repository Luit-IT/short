# URL Shortener using Varnish and Redis

This URL shortener is a personal project to have an URL shortener that runs
with the stuff I already have.  The interface to the shortener is a Go
program, with either a web- or command-line interface (to be determined).  The
links are to be handled by Varnish by connecting to [Redis][], where the data
is stored.

[Redis]: http://redis.io/


## Overall architecture

A URL shortener is by definition a key->value based system. As you might know,
Redis is "an open source, advanced key-value store", according to it's
website. For what this URL shortener should become it's a good fit. It
features simple but powerful commands, lightning-fast and predictable
performance (the documentation shows the big-O complexity for each command),
and even though it's an in-memory database it has a range of very good
[persistence][] options. Also there's a good set of language bindings, and the
C library [hiredis][] is very easy to use.

On one side a URL shortener, like the name, shortens URLs by inserting
key->value pairs into storage. On the other side a URL shortener forwards
requests by doing a lookup of the key supplied in the request URL, and
returning a HTTP redirect response to the URL that was stored. The lookup and
redirect part will be a Varnish module/configuration, connecting directly to
Redis. The insertion part can be anything with access to the Redis database.
Command-line tools, web-apps, redis-cli with hand-issued commands, anything!

[persistence]: http://redis.io/topics/persistence
[hiredis]: https://github.com/antirez/hiredis


## Redis storage format

Redis could handle the key->value combinations as [Strings][], but after
reading how [Instagram][] used Redis to map [300 photos back to the user ID][]
it was clear to me that using Redis [Hashes][] was a better option. I don't
really expect my own URL shortener to be impacted much by this. Who knows,
maybe it will.

The keys are split up in a slightly different way than what Instagram did. The
name of the hash is something like "shortener-" or "short:", with `n`
characters of the key appended. The keys used inside the Hashes are stripped
from those first `n` characters. Therefore: the key `Lm25`, will yield the URL
`http://luit.it/` when the Redis command `HGET short:Lm 25` is executed, when
the key prefix is "short:" + two characters.

[Strings]: http://redis.io/topics/data-types#strings
[Instagram]: http://instagr.am/
[300 photos back to the user ID]: http://luit.it/l/sHvK
[Hashes]:  http://redis.io/topics/data-types#hashes


## Key generation

To generate a key for a new URL, the URL is hashed and the hash digest is
encoded. Any hashing algorithm will do, as long as the encoding used for the
resulting digest is URL-safe. I'm using SHA1 to hash the URL and a URL-safe
variant on base64 to encode it's digest. The result is a 20 byte binary
digest, turned into a 28 byte base64 encoded key. When inserting this key into
Redis it can be truncated to the shortest key that isn't yet present in the
database. See the section "Inserting into Redis" below.

Another way to store a URL is to use a prefabricated key. This key shouldn't
be truncated to it's shortest unique value, but be stored as-is. This can be
used to make more readable short URLs, for example to put up on a slide in a
presentation.


## Inserting into Redis

As mentioned in the "Key generation" section the generated key doesn't always
have to be used in full. If for example a relatively short URL like
`http://canyoucrackit.co.uk/soyoudidit.asp` is hashed it produces the hash
`Nw9W82DjTt_wGeaVNpNqV8fuF0E=` when using the key generation scheme described
above. With this key appended to the URL shortener's own address it produces a
URL like `http://luit.it/l/Nw9W82DjTt_wGeaVNpNqV8fuF0E=`, which isn't much
shorter than the original. It's actually longer.

To avoid too much checking there's a minimal length of the used key. I'm using
a minimal key length of 4 characters. When inserting a URL into the database
the first 4 characters are used to lookup what's in the database already. If
there's nothing there yet, then we've got ourselves a new and shorter key. If
there already is something there, we might want to check what it is. It might
happen that the URL stored in that spot is actually the same we're trying to
store now. If it is, we're done already, and all we need to do is return the
already stored key to the user. When it isn't, we take a slightly longer slice
of the key and try the same with that. Already present is okay, something else
means we need a longer key.

If the key shouldn't be truncated (with a prefabricated key, described in the
"Key generation" section) then we simply try to lookup the key. If it doesn't
return anything it's fine and we'll store the new URL under that key. If it
does exist, and the URL returned is different from what we're trying to store
then we're in trouble. It's then probably best to show the user what's up, and
let him/her decide.

In the example shown above, we'll have to check whether the key `Nw9W` is in
use. If it isn't then we can use it for this URL. If it is, and the URL using
that key isn't what we're trying to store then we try `Nw9W8`. This game can
go on for quite a while if there's millions and millions of URLs stored
already. Realistically though, four characters of base64 encoded data can hold
16 million combinations, and with a fifth character you're up to a billion.

To avoid having multiple storage actions collide we'll have to use some sort
of locking. Fortunately Redis supports [Transactions][], which will make this
quite easy, and even performant. Having keys split up in `64^2 = 4096`
separate Redis Hashes the locking/transaction will only have an effect on
`1/4096`th of the keys. Furthermore using a transaction is only necessary when
writing, and won't need to block reads in this application. This means we'll
probably run into the performance limit of Redis well before we'll run into
limits imposed by this locking. The application does need to observe this
transaction and retry if it does fail (e.g. when another write to the same
Redis Hash is done during our transaction).

[Transactions]: http://redis.io/topics/transactions


## Lookup

Lookup of a URL is quite straight forward. The incoming URL looks something
like `http://luit.it/l/sHvK`. There's several ways you can handle this. You
could take *anything* that's given after `http://luit.it/l/` and use it as our
key, but that might give us some issues with excessively long or otherwise
evilly fabricated URLs. In varnish using regular expression substitution to
generate the Redis command will avoid the lookup of keys that are too short
(length 2 or shorter might be harmful), or contain characters we're not
expecting.

All that's to be done in the lookup is run one command on Redis. For the
example given above this is `HGET short:sH vK`, given the same situation shown
in the section "Redis storage format". If this lookup returns something, a
HTTP redirect response should be issued. If it doesn't, it's a 404 Not Found.


## TODO / DONE

Just about everything! The tools pyshort and src/add/main.go generate hashes
at the moment, usable for inserting by hand using the returned hash.

As for lookup and redirect, so-far I have built something that works in
[Inline C][] in the configuration (VCL), changing the init script to include
configuration compiler flags to dynamically link to [hiredis][]. This
configuration is [posted here][].

The next phase was to avoid the complicated VCL stuff (compiler flag stuff)
and also improving on performance and overhead by re-using the connection to
Redis. Luckily you can make a [VMOD][] to handle the C part, so you can access
your exported C functions from VCL. Using [libvmod-redis][] and configuring
Varnish [like this][] it'll do something similar to the ugly VCL with Inline
C. One problem with libvmod-redis: it connects with the first command issued
and keeps this connection open, which is actually a good thing, but when the
Redis server disconnects, all commands will fail from that moment onwards.
Luckily, after adding [some code][] to libvmod-redis it now reconnects
whenever it detects a dropped connection when trying to issue a command.

The [newest version][] of this libvmod-redis using VCL now does a curveball to
make it's redirect response cacheable. (looks like anything coming from
vcl_error won't cache)

Still missing from the response: the right code (Moved Permanently instead of
Found), some caching headers, and last but not least: generate it from the
application used to insert the information, based on it's configuration.

[Inline C]: http://luit.it/l/7ofl
[posted here]: https://gist.github.com/1415852
[VMOD]: https://www.varnish-cache.org/docs/3.0/reference/vmod.html
[libvmod-redis]: https://github.com/zephirworks/libvmod-redis
[like this]: https://gist.github.com/1431098
[some code]: https://gist.github.com/1430331
[newest version]: https://gist.github.com/1431462
