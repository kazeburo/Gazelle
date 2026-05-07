use strict;
use warnings;
use Test::TCP;
use IO::Socket::INET;
use HTTP::Response;
use Plack::Loader;
use Test::More;

# RFC 7230 §3.3.3: when both Transfer-Encoding and Content-Length are
# present, Transfer-Encoding must override Content-Length.
test_tcp(
    client => sub {
        my $port = shift;

        my $socket = IO::Socket::INET->new(
            PeerAddr => "localhost:$port",
            Proto    => 'tcp',
        ) or die "Failed to connect: $!";

        # Chunked body encodes "Hello World" (0xb = 11 bytes).
        # Content-Length: 5 is intentionally wrong — it must be ignored.
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
        # request shuold be ignored
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