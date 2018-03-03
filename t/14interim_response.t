use strict;
use warnings;
use Test::More;
use Test::TCP qw(test_tcp);
use IO::Socket::INET;
use Plack::Loader;

test_tcp(
    client => sub {
        my $port = shift;
        my $sock = IO::Socket::INET->new(
            PeerAddr => "localhost:$port",
            Proto => 'tcp',
        );

        my $req = "GET / HTTP/1.1\015\012\015\012";
        $sock->syswrite($req, length $req);

        my $resp = "";
        while ($sock->sysread($resp, 65536, length $resp)) {}

        my $expected_interim = <<"EOT";
HTTP/1\.1 100 Continue\015
foo: 123\015
bar: 456\015
\015
EOT
        is substr($resp, 0, length $expected_interim), $expected_interim;
        like substr($resp, length $expected_interim), qr{^HTTP/1\.1 200 OK\015\012}is;
    },
    server => sub {
        my $port = shift;
        my $loader = Plack::Loader->load('Gazelle', port => $port);
        $loader->run(sub {
            my $env = shift;
            $env->{"psgix.informational"}->(100, [foo => 123, bar => 456]);
            [200, ['Content-Type' => 'text/plain'], ["OK"]];
        });
        exit;
    },
);

done_testing;
