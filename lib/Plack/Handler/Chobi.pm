package Plack::Handler::Chobi;

use 5.008005;
use strict;
use warnings;
use Carp ();
use HTTP::Parser::XS qw(parse_http_request);
use IO::Socket::INET;
use List::Util qw(max sum);
use Plack::Util;
use Stream::Buffered;
use POSIX qw(EINTR EAGAIN EWOULDBLOCK);
use Socket qw(IPPROTO_TCP TCP_NODELAY);
use Parallel::Prefork;
use Server::Starter ();
use AnyEvent::Util qw/fh_nonblocking/;
use Try::Tiny;
use Time::HiRes qw(time);

our $VERSION = "0.01";

use constant MAX_REQUEST_SIZE => 131072;
use constant CHUNKSIZE        => 64 * 1024;

my $null_io = do { open my $io, "<", \""; $io };
my $bad_response = [ 400, [ 'Content-Type' => 'text/plain', 'Connection' => 'close' ], [ 'Bad Request' ] ];
my $psgi_version = [1,1];

my $TRUE = Plack::Util::TRUE;
my $FALSE = Plack::Util::FALSE;

my @DoW = qw(Sun Mon Tue Wed Thu Fri Sat);
my @MoY = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

# Unmarked codes are from RFC 2616
# See also: http://en.wikipedia.org/wiki/List_of_HTTP_status_codes

my %StatusCode = (
    100 => 'Continue',
    101 => 'Switching Protocols',
    102 => 'Processing',                      # RFC 2518 (WebDAV)
    200 => 'OK',
    201 => 'Created',
    202 => 'Accepted',
    203 => 'Non-Authoritative Information',
    204 => 'No Content',
    205 => 'Reset Content',
    206 => 'Partial Content',
    207 => 'Multi-Status',                    # RFC 2518 (WebDAV)
    208 => 'Already Reported',		      # RFC 5842
    300 => 'Multiple Choices',
    301 => 'Moved Permanently',
    302 => 'Found',
    303 => 'See Other',
    304 => 'Not Modified',
    305 => 'Use Proxy',
    307 => 'Temporary Redirect',
    400 => 'Bad Request',
    401 => 'Unauthorized',
    402 => 'Payment Required',
    403 => 'Forbidden',
    404 => 'Not Found',
    405 => 'Method Not Allowed',
    406 => 'Not Acceptable',
    407 => 'Proxy Authentication Required',
    408 => 'Request Timeout',
    409 => 'Conflict',
    410 => 'Gone',
    411 => 'Length Required',
    412 => 'Precondition Failed',
    413 => 'Request Entity Too Large',
    414 => 'Request-URI Too Large',
    415 => 'Unsupported Media Type',
    416 => 'Request Range Not Satisfiable',
    417 => 'Expectation Failed',
    418 => 'I\'m a teapot',		      # RFC 2324
    422 => 'Unprocessable Entity',            # RFC 2518 (WebDAV)
    423 => 'Locked',                          # RFC 2518 (WebDAV)
    424 => 'Failed Dependency',               # RFC 2518 (WebDAV)
    425 => 'No code',                         # WebDAV Advanced Collections
    426 => 'Upgrade Required',                # RFC 2817
    428 => 'Precondition Required',
    429 => 'Too Many Requests',
    431 => 'Request Header Fields Too Large',
    449 => 'Retry with',                      # unofficial Microsoft
    500 => 'Internal Server Error',
    501 => 'Not Implemented',
    502 => 'Bad Gateway',
    503 => 'Service Unavailable',
    504 => 'Gateway Timeout',
    505 => 'HTTP Version Not Supported',
    506 => 'Variant Also Negotiates',         # RFC 2295
    507 => 'Insufficient Storage',            # RFC 2518 (WebDAV)
    509 => 'Bandwidth Limit Exceeded',        # unofficial
    510 => 'Not Extended',                    # RFC 2774
    511 => 'Network Authentication Required',
);

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
        keepalive_timeout    => $args{keepalive_timeout} || 10,
        disable_keepalive    => (exists $args{keepalive} && !$args{keepalive}) ? 1 : 0,
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

            my $keepalive;
            my $may_keepalive;
            my $stderr = *STDERR;
            my $server_port = $self->{port} || 0;
            my $server_host = $self->{host} || 0;

            my $proc_req_count = 0;
            $self->{can_exit} = 1;
            local $SIG{TERM} = sub {
                exit 0 if $self->{can_exit};
                $self->{term_received}++;
                exit 0
                    if ( $self->{can_exit} || $self->{term_received} > 1 );
            };
            
            local $SIG{PIPE} = 'IGNORE';
            
            while ( $proc_req_count < $max_reqs_per_child) {
                if ( my $peer = accept(my $conn,$self->{listen_sock})  ) {
                    fh_nonblocking($conn,1);
                    my ($peerport, $peerhost, $peeraddr) = (0, undef, undef);
                    if ($self->{_listen_sock_is_tcp}) {
                        setsockopt($conn, IPPROTO_TCP, TCP_NODELAY, 1)
                            or die "setsockopt(TCP_NODELAY) failed:$!";
                        ($peerport, $peerhost) = unpack_sockaddr_in $peer;
                        $peeraddr = inet_ntoa($peerhost);
                    }
                    my $pipelined_buf = '';
                    my $req_count = 0;
                    while (1) {
                        ++$req_count;
                        ++$proc_req_count;
                        my $env = {
                            'REMOTE_ADDR'  => $peeraddr,
                            'REMOTE_PORT'  => $peerport,
                            'SERVER_PORT'  => $server_port,
                            'SERVER_NAME'  => $server_host,
                            'SCRIPT_NAME'  => '',
                            'psgi.version' => $psgi_version,
                            'psgi.errors'  => $stderr,
                            'psgi.url_scheme'   => 'http',
                            'psgi.run_once'     => $FALSE,
                            'psgi.multithread'  => $FALSE,
                            'psgi.multiprocess' => $TRUE,
                            'psgi.streaming'    => $TRUE,
                            'psgi.nonblocking'  => $FALSE,
                            'psgix.input.buffered' => $TRUE,
                            'psgix.harakiri'    => 1,
                        };

                        # stop keepalive if SIG{TERM} or SIG{USR1}. but go-on if pipline req
                        $may_keepalive = 1;
                        $may_keepalive = 0 if ($self->{term_received} || $self->{disable_keepalive});
                        $may_keepalive = 0 if $proc_req_count >= $max_reqs_per_child;
                        ($keepalive, $pipelined_buf) = $self->handle_connection($env, $conn, $app, 
                                                                            $may_keepalive, $req_count == 1,
                                                                            $pipelined_buf);
                        last unless $keepalive;
                    }
                    return if $self->{'harakiri.commit'};
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

sub handle_connection {
    my($self, $env, $conn, $app, $use_keepalive, $is_keepalive, $prebuf) = @_;
    
    my $buf = '';
    my $pipelined_buf='';
    my $res = $bad_response;

    local $self->{can_exit} = (defined $prebuf) ? 0 : 1;
    while (1) {
        my $rlen;
        if ( $rlen = length $prebuf ) {
            $buf = $prebuf;
            undef $prebuf;
        }
        else {
            $rlen = $self->read_timeout(
                $conn, \$buf, MAX_REQUEST_SIZE - length($buf), length($buf),
                $is_keepalive ? $self->{keepalive_timeout} : $self->{timeout},
            ) or return;
        }
        $self->{can_exit} = 0;
        my $reqlen = parse_http_request($buf, $env);
        if ($reqlen >= 0) {
            # handle request
            my $protocol = $env->{SERVER_PROTOCOL};
            if ($use_keepalive) {
                if ( $protocol eq 'HTTP/1.1' ) {
                    if (my $c = $env->{HTTP_CONNECTION}) {
                        $use_keepalive = undef 
                            if $c =~ /^\s*close\s*/i;
                    }
                }
                else {
                    if (my $c = $env->{HTTP_CONNECTION}) {
                        $use_keepalive = undef
                            unless $c =~ /^\s*keep-alive\s*/i;
                    } else {
                        $use_keepalive = undef;
                    }
                }
            }
            $buf = substr $buf, $reqlen;
            my $chunked = do { no warnings; lc delete $env->{HTTP_TRANSFER_ENCODING} eq 'chunked' };
            if (my $cl = $env->{CONTENT_LENGTH}) {
                my $buffer = Stream::Buffered->new($cl);
                while ($cl > 0) {
                    my $chunk;
                    if (length $buf) {
                        $chunk = $buf;
                        $buf = '';
                    } else {
                        $self->read_timeout(
                            $conn, \$chunk, $cl, 0, $self->{timeout})
                            or return;
                    }
                    $buffer->print($chunk);
                    $cl -= length $chunk;
                }
                $env->{'psgi.input'} = $buffer->rewind;
            }
            elsif ($chunked) {
                my $buffer = Stream::Buffered->new;
                my $chunk_buffer = '';
                my $length;
                DECHUNK: while(1) {
                    my $chunk;
                    if ( length $buf ) {
                        $chunk = $buf;
                        $buf = '';
                    }
                    else {
                        $self->read_timeout($conn, \$chunk, CHUNKSIZE, 0, $self->{timeout})
                            or return;
                    }

                    $chunk_buffer .= $chunk;
                    while ( $chunk_buffer =~ s/^(([0-9a-fA-F]+).*\015\012)// ) {
                        my $trailer   = $1;
                        my $chunk_len = hex $2;
                        if ($chunk_len == 0) {
                            last DECHUNK;
                        } elsif (length $chunk_buffer < $chunk_len + 2) {
                            $chunk_buffer = $trailer . $chunk_buffer;
                            last;
                        }
                        $buffer->print(substr $chunk_buffer, 0, $chunk_len, '');
                        $chunk_buffer =~ s/^\015\012//;
                        $length += $chunk_len;                        
                    }
                }
                $env->{CONTENT_LENGTH} = $length;
                $env->{'psgi.input'} = $buffer->rewind;
            } else {
                if ( $buf && $buf =~ m!^(?:GET|HEAD)! ) { #pipeline
                    $pipelined_buf = $buf;
                    $use_keepalive = 1; #force keepalive
                } # else clear buffer
                $env->{'psgi.input'} = $null_io;
            }

            if ( $env->{HTTP_EXPECT} ) {
                if ( $env->{HTTP_EXPECT} eq '100-continue' ) {
                    $self->write_all($conn, "HTTP/1.1 100 Continue\015\012\015\012")
                        or return;
                } else {
                    $res = [417,[ 'Content-Type' => 'text/plain', 'Connection' => 'close' ], [ 'Expectation Failed' ] ];
                    last;
                }
            }

            $res = Plack::Util::run_app $app, $env;
            last;
        }
        if ($reqlen == -2) {
            # request is incomplete, do nothing
        } elsif ($reqlen == -1) {
            # error, close conn
            last;
        }
    }

    if ( $env->{'psgix.harakiri.commit'} ) {
        $self->{'harakiri.commit'} = 1;
        $use_keepalive = undef if length($pipelined_buf) == 0;
    }

    if (ref $res eq 'ARRAY') {
        $self->_handle_response($env->{SERVER_PROTOCOL}, $res, $conn, \$use_keepalive);
    } elsif (ref $res eq 'CODE') {
        $res->(sub {
            $self->_handle_response($env->{SERVER_PROTOCOL}, $_[0], $conn, \$use_keepalive);
        });
    } else {
        die "Bad response $res";
    }
    if ($self->{term_received}) {
        exit 0;
    }
    
    return ($use_keepalive, $pipelined_buf);
}

sub _handle_response {
    my($self, $protocol, $res, $conn, $use_keepalive_r) = @_;
    my $status_code = $res->[0];
    my $headers = $res->[1];
    my $body = $res->[2];
    
    my @lines;
    my %send_headers;
    for (my $i = 0; $i < @$headers; $i += 2) {
        my $k = $headers->[$i];
        my $v = $headers->[$i + 1];
        my $lck = lc $k;
        if ($lck eq 'connection') {
            $$use_keepalive_r = undef
                if $$use_keepalive_r && lc $v ne 'keep-alive';
        } else {
            push @lines, "$k: $v\015\012";
            $send_headers{$lck} = $v;
        }
    }

    if ( !$self->{disable_date_header} && ! exists $send_headers{date} ) {
        my @lt = gmtime();
        unshift @lines, sprintf("Date: %s, %02d %s %04d %02d:%02d:%02d GMT\015\012",
                                $DoW[$lt[6]], $lt[3], $MoY[$lt[4]], $lt[5]+1900, $lt[2], $lt[1], $lt[0]);
    }

    # try to set content-length when keepalive can be used, or disable it
    my $use_chunked;
    if ( $protocol eq 'HTTP/1.0' ) {
        if ($$use_keepalive_r) {
            if (defined $send_headers{'content-length'}
                || defined $send_headers{'transfer-encoding'}) {
                # ok
            }
            elsif ( !($status_code < 200 || $status_code == 204 || $status_code == 304)
                    && defined(my $cl = Plack::Util::content_length($body))) {
                push @lines, "Content-Length: $cl\015\012";
            }
            else {
                $$use_keepalive_r = undef
            }            
        }
        push @lines, "Connection: keep-alive\015\012" if $$use_keepalive_r;
        push @lines, "Connection: close\015\012" if !$$use_keepalive_r; #fmm..
    }
    elsif ( $protocol eq 'HTTP/1.1' ) {
        if (defined $send_headers{'content-length'}
                || defined $send_headers{'transfer-encoding'}) {
            # ok
        } elsif ( !($status_code < 200 || $status_code == 204 || $status_code == 304) ) {
            push @lines, "Transfer-Encoding: chunked\015\012";
            $use_chunked = 1;
        }
        push @lines, "Connection: close\015\012" unless $$use_keepalive_r;

    }

    unshift @lines, "HTTP/1.1 $status_code $StatusCode{$status_code}\015\012";
    push @lines, "\015\012";
    
    if (defined $body && ref $body eq 'ARRAY' && @$body == 1
            && length $body->[0] < 8192) {
        # combine response header and small request body
        my $buf = $body->[0];
        if ($use_chunked ) {
            my $len = length $buf;
            $buf = sprintf("%x",$len) . "\015\012" . $buf . "\015\012" . '0' . "\015\012\015\012";
        }
        $self->write_all(
            $conn, join('', @lines, $buf), $self->{timeout},
        );
        return;
    }
    $self->write_all($conn, join('', @lines), $self->{timeout})
        or return;

    if (defined $body) {
        my $failed;
        my $completed;
        my $body_count = (ref $body eq 'ARRAY') ? $#{$body} + 1 : -1;
        Plack::Util::foreach(
            $body,
            sub {
                unless ($failed) {
                    my $buf = $_[0];
                    --$body_count;
                    if ( $use_chunked ) {
                        my $len = length $buf;
                        return unless $len;
                        $buf = sprintf("%x",$len) . "\015\012" . $buf . "\015\012";
                        if ( $body_count == 0 ) {
                            $buf .= '0' . "\015\012\015\012";
                            $completed = 1;
                        }
                    }
                    $self->write_all($conn, $buf, $self->{timeout})
                        or $failed = 1;
                }
            },
        );
        $self->write_all($conn, '0' . "\015\012\015\012", $self->{timeout}) if $use_chunked && !$completed;
    } else {
        return Plack::Util::inline_object
            write => sub {
                my $buf = $_[0];
                if ( $use_chunked ) {
                    my $len = length $buf;
                    return unless $len;
                    $buf = sprintf("%x",$len) . "\015\012" . $buf . "\015\012"
                }
                $self->write_all($conn, $buf, $self->{timeout})
            },
            close => sub {
                $self->write_all($conn, '0' . "\015\012\015\012", $self->{timeout}) if $use_chunked;
            };
    }
}


sub read_timeout {
    my ($self, $sock, $buf, $len, $off, $timeout) = @_;
    my $ret;
 DO_READ:
    $ret = sysread $sock, $$buf, $len, $off
        and return $ret;
    unless ((! defined($ret)
                 && ($! == EINTR || $! == EAGAIN || $! == EWOULDBLOCK))) {
        return;
    }
    while (1) {
        my ($rfd, $wfd);
        my $efd = '';
        vec($efd, fileno($sock), 1) = 1;
        ($rfd, $wfd) = ($efd, '');
        my $start_at = time;
        my $nfound = select($rfd, $wfd, $efd, $timeout);
        $timeout -= (time - $start_at);
        last if $nfound;
        return if $timeout <= 0;
    }
    goto DO_READ;
}

sub write_timeout {
    my ($self, $sock, $buf, $len, $off, $timeout) = @_;
    my $ret;
 DO_WRITE:
    $ret = syswrite $sock, $buf, $len, $off
        and return $ret;
    unless ((! defined($ret)
                 && ($! == EINTR || $! == EAGAIN || $! == EWOULDBLOCK))) {
        return;
    }
    while (1) {
        my ($rfd, $wfd);
        my $efd = '';
        vec($efd, fileno($sock), 1) = 1;
        ($rfd, $wfd) = ('', $efd);
        my $start_at = time;
        my $nfound = select($rfd, $wfd, $efd, $timeout);
        $timeout -= (time - $start_at);
        last if $nfound;
        return if $timeout <= 0;
    }
    goto DO_READWRITE;
}

sub write_all {
    my ($self, $sock, $buf, $timeout) = @_;
    my $off = 0;
    while (my $len = length($buf) - $off) {
        my $ret = $self->write_timeout($sock, $buf, $len, $off, $timeout)
            or return;
        $off += $ret;
    }
    return length $buf;
}

1;

__END__

=encoding utf-8

=head1 NAME

Plack::Handler::Chobi - Starlet for performance freaks

=head1 SYNOPSIS

    $ plackup -s Chobi --port 5003 --max-reqs-per-child 50000 \
         -E production -a app.psgi

=head1 DESCRIPTION

Plack::Handler::Chobi is a PSGI Handler based on Starlet code.

Chobi is optimized Starlet for performance.

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

