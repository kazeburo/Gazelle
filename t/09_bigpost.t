use strict;
use warnings;
use Test::More;
use HTTP::Request::Common;
use Digest::MD5;
use t::TestUtils;


$Plack::Test::Impl = 'Server';
$ENV{PLACK_SERVER} = 'Gazelle';

sub test_bigpost {
    test_psgi
        client => sub {
            my $cb = shift;
            my $chunk = "abcdefgh" x 12_000;
            my $req = HTTP::Request->new(POST => "http://127.0.0.1/");
            $req->content_length(length $chunk);
            $req->content_type('application/octet-stream');
            $req->content($chunk);

            my $res = $cb->($req);
            is $res->code, 200;
            is $res->message, 'OK';
            is $res->header('Client-Content-Length'), length $chunk;
            is length $res->content, length $chunk;
            is $res->header('Client-Header-Content-MD5'), Digest::MD5::md5_hex(substr($chunk,0,100)),
                "header md $t::TestUtils::HTTP_VER";
            is Digest::MD5::md5_hex($res->content), Digest::MD5::md5_hex($chunk), "md5 $t::TestUtils::HTTP_VER";
            is substr($res->content,0,100), substr($chunk,0,100), "body header $t::TestUtils::HTTP_VER";
            is substr($res->content,-100,100), substr($chunk,-100,100), "body footer $t::TestUtils::HTTP_VER";
        },
        app => sub {
            my $env = shift;
            my $len = $env->{CONTENT_LENGTH};
            my $body = '';
            my $spin;
            while ($len > 0) {
                my $rc = $env->{'psgi.input'}->read($body, $env->{CONTENT_LENGTH}, length $body);
                $len -= $rc;
                last if $spin++ > 2000;
            }
            return [
                200,
                [ 'Content-Type' => 'text/plain',
                  'Client-Content-Length' => $env->{CONTENT_LENGTH},
                  'Client-Content-Type' => $env->{CONTENT_TYPE},
                  'Client-Header-Content-MD5' => Digest::MD5::md5_hex(substr($body,0,100)),
              ],
                [ $body ],
            ];
        };
}

{
    test_bigpost();
}
{
    local $t::TestUtils::HTTP_VER = "1.0";
    test_bigpost();
}




done_testing;
