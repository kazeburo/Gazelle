# NAME

Plack::Handler::Chobi - Preforked Plack::Handler for performance freaks

# SYNOPSIS

    $ plackup -s Chobi --port 5003 --max-reqs-per-child 50000 \
         -E production -a app.psgi

# DESCRIPTION

Plack::Handler::Chobi is a PSGI Handler based on Starlet code. Many code was rewritten and optimized by XS.

Plack::Handler::Chobi's supports and does not support follwing freatures.

\- only supports HTTP/1.0. But Chobi does not support Keepalive.

\- ultra fast HTTP processing useing picohttpparser

\- uses accept4(2) if OS support

\- uses writev(2) for output responses

\- prefork and graceful shutdown using Parallel::Prefork

\- hot deploy using Server::Starter

Chobi is suitable for running HTTP application servers behind a reverse proxy link nginx.

# COMMAND LINE OPTIONS

In addition to the options supported by plackup, Chobi accepts following options(s).

## --max-workers=#

number of worker processes (default: 10)

## --timeout=#

seconds until timeout (default: 300)

## --max-reqs-per-child=#

max. number of requests to be handled before a worker process exits (default: 1000)

## --min-reqs-per-child=#

if set, randomizes the number of requests handled by a single worker process between the value and that supplied by `--max-reqs-per-chlid` (default: none)

## --spawn-interval=#

if set, worker processes will not be spawned more than once than every given seconds.  Also, when SIGHUP is being received, no more than one worker processes will be collected every given seconds.  This feature is useful for doing a "slow-restart".  See http://blog.kazuhooku.com/2011/04/web-serverstarter-parallelprefork.html for more information. (dedault: none)

## --disable-date-header

if set, Chobi will not add a Date header to response header.

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
