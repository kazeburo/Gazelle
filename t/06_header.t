use strict;
use warnings;
use Plack::Loader;
use Test::More;
use Test::TCP;
use IO::Socket::INET;
use IO::Select;

my $MAX_HEADER_LEN = 1024;
my $MAX_HEADERS    = 128;
my $crlf = "\015\012";

test_tcp(
    server => sub {
        my $port = shift;
        Plack::Loader->load('Gazelle','port'=>$port,'max_workers'=>1)->run(sub{
            my $env = shift;
            my $body='';
            for (keys %$env) {
                $body .= "$_\t".$env->{$_}."\n"
                    if $_ !~ m![a-z]! 
                   and $_ !~ m!^(REMOTE|SERVER)_(HOST|PORT|ADDR|NAME)$!
                   and $_ ne "HTTP_X_FORWARDED_FOR";
            }
            [ 200, [ 'Content-Type' => 'text/plain' ], [ $body ] ]
        });
        exit;
    },
    client => sub {
        my ($port, $server_pid) = @_;
        my $requester = sub {
            my $request = shift;
            my $sock = IO::Socket::INET->new(
                PeerAddr => '127.0.0.1:'.$port,
                Proto    => 'tcp',
                Timeout => 5,
            );
            $sock->blocking(0);
            my $r = IO::Select->new($sock);
            $r->can_write(5);
            $sock->syswrite($request);
            $r->can_read(5);
            my $buf='';
            $sock->sysread($buf,4096);
            my ($header,$body) = split /\r\n\r\n/, $buf, 2;
            no warnings;
            my ($status_header) = split /\r\n/, $header;
            if ( $status_header !~ m!200 OK! ) {
                return {};
            }
            my %env;
            for (split /\n/, $body) {
                my ($k,$v) = split /\t/, $_, 2;
                $env{$k} = $v;
            }
            return \%env;
        };

        my $req = "GET /abc?x=%79 HTTP/1.0\r\n\r\n";
        is_deeply($requester->($req), {
            PATH_INFO       => '/abc',
            QUERY_STRING    => 'x=%79',
            REQUEST_METHOD  => "GET",
            REQUEST_URI     => '/abc?x=%79',
            SCRIPT_NAME     => '',
            SERVER_PROTOCOL => 'HTTP/1.0',
        }, 'result of GET /');

        $req = <<"EOT";
POST /hoge HTTP/1.1\r
Content-Type: text/plain\r
Content-Length: 15\r
Host: example.com\r
User-Agent: hoge\r
\r
xxxxxxxxxxxxxxx
EOT
        is_deeply($requester->($req), {
            CONTENT_LENGTH  => 15,
            CONTENT_TYPE    => 'text/plain',
            HTTP_HOST       => 'example.com',
            HTTP_USER_AGENT => 'hoge',
            PATH_INFO       => '/hoge',
            REQUEST_METHOD  => "POST",
            REQUEST_URI     => '/hoge',
            QUERY_STRING    => '',
            SCRIPT_NAME     => '',
            SERVER_PROTOCOL => 'HTTP/1.1',
        }, 'result of POST with headers');

        $req = <<"EOT";
GET / HTTP/1.0\r
Foo: \r
Foo: \r
  abc\r
 de\r
Foo: fgh\r
\r
EOT
        is_deeply($requester->($req), {
            HTTP_FOO        => ',   abc de, fgh',
            PATH_INFO       => '/',
            QUERY_STRING    => '',
            REQUEST_METHOD  => 'GET',
            REQUEST_URI     => '/',
            SCRIPT_NAME     => '',
            SERVER_PROTOCOL => 'HTTP/1.0',
        }, 'multiline');

        $req = <<"EOT";
GET /a%20b HTTP/1.0\r
\r
EOT
        is_deeply($requester->($req), {
            PATH_INFO      => '/a b',
            REQUEST_METHOD => 'GET',
            REQUEST_URI    => '/a%20b',
            QUERY_STRING   => '',
            SCRIPT_NAME     => '',
            SERVER_PROTOCOL => 'HTTP/1.0',
        },'url-encoded');

        $req = <<"EOT";
GET /a%2zb HTTP/1.0\r
\r
EOT
        is_deeply($requester->($req), {}, 'invalid char in url-encoded path');


        $req = <<"EOT";
GET /a%2 HTTP/1.0\r
\r
EOT
        is_deeply($requester->($req), {}, 'partially url-encoded');

        $req = <<"EOT";
GET /a/b#c HTTP/1.0\r
\r
EOT
        is_deeply($requester->($req), {
            SCRIPT_NAME => '',
            PATH_INFO   => '/a/b',
            REQUEST_METHOD => 'GET',
            REQUEST_URI    => '/a/b#c',
            QUERY_STRING   => '',
            SCRIPT_NAME     => '',
            SERVER_PROTOCOL => 'HTTP/1.0',
        }, 'URI fragment');

        $req = <<"EOT";
GET /a/b%23c HTTP/1.0\r
\r
EOT
        is_deeply($requester->($req), {
            SCRIPT_NAME => '',
            PATH_INFO   => '/a/b#c',
            REQUEST_METHOD => 'GET',
            REQUEST_URI    => '/a/b%23c',
            QUERY_STRING   => '',
            SCRIPT_NAME     => '',
            SERVER_PROTOCOL => 'HTTP/1.0',
        }, 'URI fragment');

        $req = <<"EOT";
GET /a/b?c=d#e HTTP/1.0\r
\r
EOT
        is_deeply($requester->($req), {
            SCRIPT_NAME => '',
            PATH_INFO   => '/a/b',
            REQUEST_METHOD => 'GET',
            REQUEST_URI    => '/a/b?c=d#e',
            QUERY_STRING   => 'c=d',
            SCRIPT_NAME     => '',
            SERVER_PROTOCOL => 'HTTP/1.0',
        }, 'URI fragment after query string');

        my $name = 'x' x $MAX_HEADER_LEN; # OK
        $req = "GET / HTTP/1.1" . $crlf
            . "$name: 42" . $crlf
            . $crlf;
        my $env = $requester->($req);
        is $env->{REQUEST_METHOD}, 'GET';
        is $env->{'HTTP_' . uc $name}, 42, 'very long name';

        $name = 'x' x ($MAX_HEADER_LEN + 1);
        $req = "GET / HTTP/1.1" . $crlf
          . "$name: 42" . $crlf
          . $crlf;
        $env = $requester->($req);
        is $env->{REQUEST_METHOD}, undef;
        is $env->{'HTTP_' . uc $name}, undef, 'too long name';

        $req = "GET / HTTP/1.1" . $crlf
          . join($crlf, map { "X$_: $_" } 0 .. $MAX_HEADERS) . $crlf
          . $crlf;
        is_deeply($requester->($req),{}, 'too many headers')

    }
);

done_testing;
