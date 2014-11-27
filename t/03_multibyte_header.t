use strict;
use warnings;
use Plack::Loader;
use Test::More;
use Test::TCP;
use IO::Socket::INET;
use IO::Select;

my $req1 = "GET /foo/bar HTTP/1.1\r\nHost: example.com\r\n\r\n";
my $req2 = "GET /foo/プラック HTTP/1.1\r\nHost: example.com\r\nReferer: http://example.com/\r\n\r\n";
my $req3 = "GET /foo/bar HTTP/1.1\r\nHost: example.com\r\nReferer: http://プラック.com/\r\n\r\n";

test_tcp(
    server => sub {
        my $port = shift;
        Plack::Loader->load('Gazelle','port'=>$port,'max_workers'=>1)->run(sub{
            [ 200, [ 'Content-Type' => 'text/plain' ], [ "hello world $$" ] ]
        });
        exit;
    },
    client => sub {
        my ($port, $server_pid) = @_;
        my $pid;
        {
            my $sock = IO::Socket::INET->new(
                PeerAddr => '127.0.0.1:'.$port,
                Proto    => 'tcp',
                Timeout => 5,
            );
            $sock->blocking(0);
            my $r = IO::Select->new($sock);
            $r->can_write(5);
            $sock->syswrite($req1);
            $r->can_read(5);
            my $buf='';
            $sock->sysread($buf,4096);
            like $buf, qr/hello world/, 'req1';
            if ( $buf =~ m!hello world (\d+)! ) {
                $pid = $1;
            }
        }

        {
            my $sock = IO::Socket::INET->new(
                PeerAddr => '127.0.0.1:'.$port,
                Proto    => 'tcp',
                Timeout => 5,
            );
            $sock->blocking(0);
            my $r = IO::Select->new($sock);
            $r->can_write(5);
            $sock->syswrite($req2);
            $r->can_read(5);
            my $buf='';
            $sock->sysread($buf,4096);
            like $buf, qr/hello world/, 'req2';
        }


        {
            my $sock = IO::Socket::INET->new(
                PeerAddr => '127.0.0.1:'.$port,
                Proto    => 'tcp',
                Timeout => 5,
            );
            $sock->blocking(0);
            my $r = IO::Select->new($sock);
            $r->can_write(5);
            $sock->syswrite($req3);
            $r->can_read(5);
            my $buf='';
            $sock->sysread($buf,4096);
            like $buf, qr/hello world/, 'req3';
        }
        kill 'KILL', $pid;
    }
);

done_testing;

