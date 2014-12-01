# NAME

Gazelle - Preforked Plack Handler for performance freaks

# SYNOPSIS

    $ plackup -s Gazelle --port 5003 --max-reqs-per-child 50000 \
         -E production -a app.psgi

# DESCRIPTION

Gazelle is a PSGI Handler. It's created based on [Starlet](https://metacpan.org/pod/Starlet) code. 
Many code was rewritten and optimized by XS.

Gazelle supports following features.

\- only supports HTTP/1.0. But does not support Keepalive.

\- ultra fast HTTP processing using picohttpparser

\- uses accept4(2) if OS support

\- uses writev(2) for output responses

\- prefork and graceful shutdown using Parallel::Prefork

\- hot deploy and unix domain socket using Server::Starter

Gazelle is suitable for running HTTP application servers behind a reverse proxy like nginx.

Benchmark is here. https://github.com/kazeburo/Gazelle/wiki/Benchmark

# SAMPLE CONFIGURATION WITH NGINX

nginx.conf

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

start\_server is bundled with [Server::Starter](https://metacpan.org/pod/Server::Starter)

# COMMAND LINE OPTIONS

In addition to the options supported by plackup, Gazelle accepts following options(s).

## --max-workers=#

number of worker processes (default: 10)

## --timeout=#

seconds until timeout (default: 300)

## --max-reqs-per-child=#

max. number of requests to be handled before a worker process exits (default: 1000)

## --min-reqs-per-child=#

if set, randomizes the number of requests handled by a single worker process between the value and that supplied by `--max-reqs-per-chlid` (default: none)

## --spawn-interval=#

if set, worker processes will not be spawned more than once than every given seconds.  Also, when SIGHUP is being received, no more than one worker processes will be collected every given seconds.  This feature is useful for doing a "slow-restart".  See http://blog.kazuhooku.com/2011/04/web-serverstarter-parallelprefork.html for more information. (default: none)

# SEE ALSO

[Starlet](https://metacpan.org/pod/Starlet)
[Parallel::Prefork](https://metacpan.org/pod/Parallel::Prefork)
[Server::Starter](https://metacpan.org/pod/Server::Starter)
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
