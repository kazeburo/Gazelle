package Gazelle;

use 5.008005;
use strict;
use warnings;

our $VERSION = "0.03";

1;

__END__

=encoding utf-8

=head1 NAME

Gazelle - Preforked Plack Handler for performance freaks

=head1 SYNOPSIS

    $ plackup -s Gazelle --port 5003 --max-reqs-per-child 50000 \
         -E production -a app.psgi

=head1 DESCRIPTION

Gazelle is a PSGI Handler. It's created based on L<Starlet> code. 
Many code was rewritten and optimized by XS.

Gazelle supports following features.

- only supports HTTP/1.0. But does not support Keepalive.

- ultra fast HTTP processing using picohttpparser

- uses accept4(2) if OS support

- uses writev(2) for output responses

- prefork and graceful shutdown using Parallel::Prefork

- hot deploy and unix domain socket using Server::Starter

Gazelle is suitable for running HTTP application servers behind a reverse proxy link nginx.

Benchmark is here. https://github.com/kazeburo/Gazelle/wiki/Benchmark

=head1 SAMPLE CONFIGURATION WITH NGINX

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

start_server is bundled with L<Server::Starter>

=head1 COMMAND LINE OPTIONS

In addition to the options supported by plackup, Gazelle accepts following options(s).

=head2 --max-workers=#

number of worker processes (default: 10)

=head2 --timeout=#

seconds until timeout (default: 300)

=head2 --max-reqs-per-child=#

max. number of requests to be handled before a worker process exits (default: 1000)

=head2 --min-reqs-per-child=#

if set, randomizes the number of requests handled by a single worker process between the value and that supplied by C<--max-reqs-per-chlid> (default: none)

=head2 --spawn-interval=#

if set, worker processes will not be spawned more than once than every given seconds.  Also, when SIGHUP is being received, no more than one worker processes will be collected every given seconds.  This feature is useful for doing a "slow-restart".  See http://blog.kazuhooku.com/2011/04/web-serverstarter-parallelprefork.html for more information. (default: none)

=head1 SEE ALSO

L<Starlet>
L<Parallel::Prefork>
L<Server::Starter>
L<https://github.com/h2o/picohttpparser>

=head1 LICENSE of Starlet 

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=head1 LICENSE

Copyright (C) Masahiro Nagano.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Masahiro Nagano E<lt>kazeburo@gmail.comE<gt>

=cut

