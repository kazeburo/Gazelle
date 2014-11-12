package Plack::Handler::Chobi;

use 5.008005;
use strict;
use warnings;
use Carp ();
use IO::Socket::INET;
use List::Util qw(max sum);
use Plack::Util;
use Stream::Buffered;
use POSIX qw(EINTR EAGAIN EWOULDBLOCK);
use Socket qw(IPPROTO_TCP TCP_NODELAY);
use Parallel::Prefork;
use Server::Starter ();
use Try::Tiny;
use Time::HiRes qw(time);
use Guard;
use HTTP::Status;
use HTTP::Date;

our $VERSION = "0.01";

use XSLoader;
XSLoader::load(__PACKAGE__, $VERSION);

use constant MAX_REQUEST_SIZE => 131072;
use constant CHUNKSIZE        => 64 * 1024;

my $null_io = do { open my $io, "<", \""; $io };
my $bad_response = [ 400, [ 'Content-Type' => 'text/plain', 'Connection' => 'close' ], [ 'Bad Request' ] ];

sub new {
    my($class, %args) = @_;

    # setup before instantiation
    my $listen_sock;
    if (defined $ENV{SERVER_STARTER_PORT}) {
        my ($hostport, $fd) = %{Server::Starter::server_ports()};
        if ($hostport =~ /(.*):(\d+)/) {
            $args{host} = $1;
            $args{port} = $2;
        } else {
            $args{port} = $hostport;
        }
        $listen_sock = IO::Socket::INET->new(
            Proto => 'tcp',
        ) or die "failed to create socket:$!";
        $listen_sock->fdopen($fd, 'w')
            or die "failed to bind to listening socket:$!";
    }

    my $max_workers = 10;
    for (qw(max_workers workers)) {
        $max_workers = delete $args{$_}
            if defined $args{$_};
    }

    my $self = bless {
        listen_sock          => $listen_sock,
        host                 => $args{host} || 0,
        port                 => $args{port} || 8080,
        timeout              => $args{timeout} || 300,
        max_workers          => $max_workers,
        disable_date_header  => (exists $args{date_header} && !$args{date_header}) ? 1 : 0,
        min_reqs_per_child   => (
            defined $args{min_reqs_per_child}
                ? $args{min_reqs_per_child} : undef,
        ),
        max_reqs_per_child   => (
            $args{max_reqs_per_child} || $args{max_requests} || 1000,
        ),
        spawn_interval       => $args{spawn_interval} || 0,
        err_respawn_interval => (
            defined $args{err_respawn_interval}
                ? $args{err_respawn_interval} : undef,
        ),
    }, $class;

    $self;
}

sub setup_listener {
    my $self = shift;
    $self->{listen_sock} ||= IO::Socket::INET->new(
        Listen    => SOMAXCONN,
        LocalPort => $self->{port},
        LocalAddr => $self->{host},
        Proto     => 'tcp',
        ReuseAddr => 1,
    ) or die "failed to listen to port $self->{port}:$!";

    my $family = Socket::sockaddr_family(getsockname($self->{listen_sock}));
    $self->{_listen_sock_is_tcp} = $family != AF_UNIX;

    # set defer accept
    if ($^O eq 'linux' && $self->{_listen_sock_is_tcp}) {
        setsockopt($self->{listen_sock}, IPPROTO_TCP, 9, 1);
    }
}


sub run {
    my($self, $app) = @_;
    $self->setup_listener();
    # use Parallel::Prefork
    my %pm_args = (
        max_workers => $self->{max_workers},
        trap_signals => {
            TERM => 'TERM',
            HUP  => 'TERM',
        },
    );
    if (defined $self->{spawn_interval}) {
        $pm_args{trap_signals}{USR1} = [ 'TERM', $self->{spawn_interval} ];
        $pm_args{spawn_interval} = $self->{spawn_interval};
    }
    if (defined $self->{err_respawn_interval}) {
        $pm_args{err_respawn_interval} = $self->{err_respawn_interval};
    }
    my $pm = Parallel::Prefork->new(\%pm_args);
    while ($pm->signal_received !~ /^(TERM|USR1)$/) {
        $pm->start(sub{
            srand((rand() * 2 ** 30) ^ $$ ^ time);

            my $max_reqs_per_child = $self->_calc_minmax_per_child(
                $self->{max_reqs_per_child},
                $self->{min_reqs_per_child}
            );

            my $proc_req_count = 0;
            $self->{can_exit} = 1;
            local $SIG{TERM} = sub {
                exit 0 if $self->{can_exit};
                $self->{term_received}++;
                exit 0
                    if ( $self->{can_exit} || $self->{term_received} > 1 );
            };
            
            local $SIG{PIPE} = 'IGNORE';
        PROC_LOOP:
            while ( $proc_req_count < $max_reqs_per_child) {
                $self->{can_exit} = 1;
                if ( my ($conn, $buf, $env) = accept_psgi(
                    fileno($self->{listen_sock}), $self->{timeout}, $self->{_listen_sock_is_tcp}, 
                    $self->{host} || 0, $self->{port} || 0
                ) ) {
                    my $guard = guard { close_client($conn) };
                    $self->{can_exit} = 0;
                    ++$proc_req_count;
                    my $res = $bad_response;

                    if (my $cl = $env->{CONTENT_LENGTH}) {
                        my $buffer = Stream::Buffered->new($cl);
                        while ($cl > 0) {
                            my $chunk;
                            if (length $buf) {
                                $chunk = $buf;
                                $buf = '';
                            } else {
                                read_timeout(
                                    $conn, \$chunk, $cl, 0, $self->{timeout})
                                    or next PROC_LOOP;
                            }
                            $buffer->print($chunk);
                            $cl -= length $chunk;
                        }
                        $env->{'psgi.input'} = $buffer->rewind;
                    } else {
                        $env->{'psgi.input'} = $null_io;
                    }
                    
                    $res = Plack::Util::run_app $app, $env;
                    
                    if (ref $res eq 'ARRAY') {
                        $self->_handle_response($res, $conn);
                    } elsif (ref $res eq 'CODE') {
                        $res->(sub {
                                   $self->_handle_response($_[0], $conn);
                               });
                    } else {
                        die "Bad response $res";
                    }
                    if ($self->{term_received} || $env->{'psgix.harakiri.commit'}) {
                        exit 0;
                    }
                }
            }
        });
    }
    $pm->wait_all_children;
}


sub _calc_minmax_per_child {
    my $self = shift;
    my ($max,$min) = @_;
    if (defined $min) {
        srand((rand() * 2 ** 30) ^ $$ ^ time);
        return $max - int(($max - $min + 1) * rand);
    } else {
        return $max;
    }
}

sub _handle_response {
    my($self, $res, $conn) = @_;
    my $status_code = $res->[0];
    my $headers = $res->[1];
    my $body = $res->[2];
    
    #my $lines = "Connection: close\015\012";
    #my $send_date;
    #for (my $i = 0; $i < @$headers; $i += 2) {
    #    my $k = $headers->[$i];
    #    my $v = $headers->[$i + 1];
    #    my $lck = lc $k;
    #    next if $lck eq 'connection';
    #    $send_date = 1 if $lck eq 'date';
    #    $lines .= "$k: $v\015\012";
    #}
    #if ( !$self->{disable_date_header} && ! $send_date ) {
    #    $lines = "Date: ".time2str() . "\015\012$lines";
    #}
    #$lines = "HTTP/1.0 $status_code ".status_message($status_code)."\015\012$lines\015\012";

    if (defined $body && ref $body eq 'ARRAY' ) {
        write_psgi_response($conn, $self->{timeout}, $status_code, $headers , $body, $self->{disable_date_header});
        return;
    }
    write_psgi_response($conn, $self->{timeout}, $status_code, $headers, [], $self->{disable_date_header}) or return;

    if (defined $body) {
        my $failed;
        Plack::Util::foreach(
            $body,
            sub {
                unless ($failed) {
                    write_all($conn, $_[0], 0, $self->{timeout})
                        or $failed = 1;
                }
            },
        );
    } else {
        return Plack::Util::inline_object
            write => sub {
                write_all($conn, $_[0], 0, $self->{timeout})
            },
            close => sub {
                #none
            };
    }
}

1;

__END__

=encoding utf-8

=head1 NAME

Plack::Handler::Chobi - Preforked Plack Handler for performance freaks

=head1 SYNOPSIS

    $ plackup -s Chobi --port 5003 --max-reqs-per-child 50000 \
         -E production -a app.psgi

=head1 DESCRIPTION

Plack::Handler::Chobi is a PSGI Handler. It's created based on L<Starlet> code. 
Many code was rewritten and optimized by XS.

Plack::Handler::Chobi's supports follwing freatures.

- only supports HTTP/1.0. But Chobi does not support Keepalive.

- ultra fast HTTP processing useing picohttpparser

- uses accept4(2) if OS support

- uses writev(2) for output responses

- prefork and graceful shutdown using Parallel::Prefork

- hot deploy and unix domain socket using Server::Starter

Chobi is suitable for running HTTP application servers behind a reverse proxy link nginx.

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

comannd line of running Chobi

  $ start_server --path /path/to/app.sock --backlog 16384 -- plackup -s Chobi \
    -workers=20 --max-reqs-per-child 1000 --min-reqs-per-child 800 -E production -a app.psgi

start_server is bundled with L<Server::Starter>

=head1 COMMAND LINE OPTIONS

In addition to the options supported by plackup, Chobi accepts following options(s).

=head2 --max-workers=#

number of worker processes (default: 10)

=head2 --timeout=#

seconds until timeout (default: 300)

=head2 --max-reqs-per-child=#

max. number of requests to be handled before a worker process exits (default: 1000)

=head2 --min-reqs-per-child=#

if set, randomizes the number of requests handled by a single worker process between the value and that supplied by C<--max-reqs-per-chlid> (default: none)

=head2 --spawn-interval=#

if set, worker processes will not be spawned more than once than every given seconds.  Also, when SIGHUP is being received, no more than one worker processes will be collected every given seconds.  This feature is useful for doing a "slow-restart".  See http://blog.kazuhooku.com/2011/04/web-serverstarter-parallelprefork.html for more information. (dedault: none)

=head2 --disable-date-header

if set, Chobi will not add a Date header to response header.

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

