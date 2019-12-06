# NAME

Gazelle - a Preforked Plack Handler for performance freaks

# SYNOPSIS

    $ plackup -s Gazelle --port 5003 --max-reqs-per-child 50000 \
         -E production -a app.psgi

# DESCRIPTION

Gazelle is a PSGI Handler. It is derivied from [Starlet](https://metacpan.org/pod/Starlet).
A lot of its code was rewritten or optimized by converting it to XS code.

Gazelle supports following features:

- Supports HTTP/1.1. (Without Keepalive support.)
- Ultra fast HTTP processing using picohttpparser.
- Uses accept4(2) if the operating system supports it.
- Uses writev(2) for output responses.
- Prefork and graceful shutdown using Parallel::Prefork.
- Hot deploy and unix domain socket using Server::Starter.

Gazelle is suitable for running HTTP application servers behind a reverse proxy
such as nginx.

One can find a Benchmark here:
[https://github.com/kazeburo/Gazelle/wiki/Benchmark](https://github.com/kazeburo/Gazelle/wiki/Benchmark) .

# SAMPLE CONFIGURATION WITH NGINX

nginx.conf:

    http {
      upstream app {
        server unix:/path/to/app.sock;
      }
      server {
        location / {
          proxy_pass http://app;
        }
        location ~ ^/(stylesheets|images)/ {
          root /path/to/webapp/public;
        }
      }
    }

command line of running Gazelle

    $ start_server --path /path/to/app.sock --backlog 16384 -- plackup -s Gazelle \
      -workers=20 --max-reqs-per-child 1000 --min-reqs-per-child 800 -E production -a app.psgi

start\_server is bundled with [Server::Starter](https://metacpan.org/pod/Server%3A%3AStarter)

# COMMAND LINE OPTIONS

In addition to the options supported by plackup, Gazelle accepts the
following options:

## --max-workers=#

Number of worker processes (default: 10).

## --timeout=#

Seconds until timeout (default: 300).

## --max-reqs-per-child=#

Maximal number of requests to be handled before a worker process exits
(default: 1000).

## --min-reqs-per-child=#

If set, randomize the number of requests handled by a single worker process
between this value and the one supplied by `--max-reqs-per-child` (default:
none).

## --spawn-interval=#

If set, worker processes will not be spawned more than once than every number
of seconds given in the parameter.  Furthermore, when a SIGHUP is being
received, no more than one worker processes will be collected during this
interval.  This feature is useful for doing a "slow-restart".  See
[http://blog.kazuhooku.com/2011/04/web-serverstarter-parallelprefork.html](http://blog.kazuhooku.com/2011/04/web-serverstarter-parallelprefork.html) for
more information. (default: none)

## --child-exit=s

the subroutine code to be executed right before a child process exits. e.g. `--child-exit='sub { POSIX::_exit(0) }'`. (default: none)

# Extensions to PSGI

## psgix.informational

Gazelle exposes a callback named `psgix.informational` that can be used for sending an informational response.
The callback accepts two arguments, the first argument being the status code and the second being an arrayref of the headers to be sent.
Example below sends an 103 response before processing the request to build a final response.
  sub {
      my $env = shift;
      $env\["psgix.informational"}->(103, \[
        'link' => '&lt;/style.css>; rel=preload'
      \]);
      my $resp = ... application logic ...
      $resp;
  }

# SEE ALSO

[Starlet](https://metacpan.org/pod/Starlet)
[Parallel::Prefork](https://metacpan.org/pod/Parallel%3A%3APrefork)
[Server::Starter](https://metacpan.org/pod/Server%3A%3AStarter)
[https://github.com/h2o/picohttpparser](https://github.com/h2o/picohttpparser)

# LICENSE of Starlet

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

See [http://www.perl.com/perl/misc/Artistic.html](http://www.perl.com/perl/misc/Artistic.html)

# LICENSE

Copyright (C) Masahiro Nagano.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Masahiro Nagano <kazeburo@gmail.com>
