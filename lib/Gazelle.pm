package Gazelle;

use 5.008001;
use strict;
use warnings;

our $VERSION = "0.49";

1;

__END__

=encoding utf-8

=head1 NAME

Gazelle - a Preforked Plack Handler for performance freaks

=head1 SYNOPSIS

    $ plackup -s Gazelle --port 5003 --max-reqs-per-child 50000 \
         -E production -a app.psgi

=head1 DESCRIPTION

Gazelle is a PSGI Handler. It is derivied from L<Starlet>.
A lot of its code was rewritten or optimized by converting it to XS code.

Gazelle supports following features:

=over

=item * Supports HTTP/1.1. (Without Keepalive support.)

=item * Ultra fast HTTP processing using picohttpparser.

=item * Uses accept4(2) if the operating system supports it.

=item * Uses writev(2) for output responses.

=item * Prefork and graceful shutdown using Parallel::Prefork.

=item * Hot deploy and unix domain socket using Server::Starter.

=back

Gazelle is suitable for running HTTP application servers behind a reverse proxy
such as nginx.

One can find a Benchmark here:
L<https://github.com/kazeburo/Gazelle/wiki/Benchmark> .

=head1 SAMPLE CONFIGURATION WITH NGINX

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

start_server is bundled with L<Server::Starter>

=head1 COMMAND LINE OPTIONS

In addition to the options supported by plackup, Gazelle accepts the
following options:

=head2 --max-workers=#

Number of worker processes (default: 10).

=head2 --timeout=#

Seconds until timeout (default: 300).

=head2 --max-reqs-per-child=#

Maximal number of requests to be handled before a worker process exits
(default: 1000).

=head2 --min-reqs-per-child=#

If set, randomize the number of requests handled by a single worker process
between this value and the one supplied by C<--max-reqs-per-child> (default:
none).

=head2 --spawn-interval=#

If set, worker processes will not be spawned more than once than every number
of seconds given in the parameter.  Furthermore, when a SIGHUP is being
received, no more than one worker processes will be collected during this
interval.  This feature is useful for doing a "slow-restart".  See
L<http://blog.kazuhooku.com/2011/04/web-serverstarter-parallelprefork.html> for
more information. (default: none)

=head2 --child-exit=s

the subroutine code to be executed right before a child process exits. e.g. C<--child-exit='sub { POSIX::_exit(0) }'>. (default: none)

=head1 Extensions to PSGI

=head2 psgix.informational

Gazelle exposes a callback named C<psgix.informational> that can be used for sending an informational response.
The callback accepts two arguments, the first argument being the status code and the second being an arrayref of the headers to be sent.
Example below sends an 103 response before processing the request to build a final response.
  sub {
      my $env = shift;
      $env["psgix.informational"}->(103, [
        'link' => '</style.css>; rel=preload'
      ]);
      my $resp = ... application logic ...
      $resp;
  }

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
