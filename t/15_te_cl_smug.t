use strict;
use warnings;
use Test::TCP;
use IO::Socket::INET;
use Plack::Loader;
use Test::More;

# RFC 7230 §3.3.3: when both Transfer-Encoding and Content-Length are
# present, Transfer-Encoding must override Content-Length.
test_tcp(
    client => sub {
        my $port = shift;

        my $socket = IO::Socket::INET->new(
            PeerAddr => "127.0.0.1:$port",
            Proto    => 'tcp',
            Timeout  => 5,
        ) or die "Failed to connect: $!";

        # If there is both Transfer-Encoding and Content-Length, the request should be ignored.
        my $chunked_body = "b\r\nHello World\r\n0\r\n\r\n";
        my $req = "POST / HTTP/1.1\r\n"
                . "Host: localhost\r\n"
                . "Transfer-Encoding: chunked\r\n"
                . "Content-Length: 5\r\n"
                . "\r\n"
                . $chunked_body;
        $socket->syswrite($req, length $req);
        my $resp = "";
        while ($socket->sysread($resp, 65536, length $resp)) {}
        # request should be ignored
        is $resp, "";
    },
    server => sub {
        my $port = shift;
        my $server = Plack::Loader->load('Gazelle', port => $port);
        $server->run(sub {
            my $env = shift;
            my $body = '';
            $env->{'psgi.input'}->read($body, 8192);
            return [ 200, [ 'Content-Type', 'text/plain', 'Content-Length', length($body) ], [ $body ] ];
        });
        exit;
    },
);

done_testing;