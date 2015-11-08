use strict;
use warnings;

use Test::More;
use Plack::Test;
use HTTP::Request::Common;
use Digest::MD5;
use HTTP::Tiny;

my $HTTP_VER = "1.1";
{
    no warnings 'redefine';
    sub HTTP::Tiny::Handle::write_request_header {
        @_ == 4 || die(q/Usage: $handle->write_request_header(method, request_uri, headers)/ . "\n");
        my ($self, $method, $request_uri, $headers) = @_;
        return $self->write_header_lines($headers, "$method $request_uri HTTP/$HTTP_VER\x0D\x0A");
    }
}

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
            is Digest::MD5::md5_hex($res->content), Digest::MD5::md5_hex($chunk), "md5 $HTTP_VER";
            is substr($res->content,0,100), substr($chunk,0,100), "body header $HTTP_VER";
            is substr($res->content,-100,100), substr($chunk,-100,100), "body footer $HTTP_VER";
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
              ],
                [ $body ],
            ];
        };
}

{
    test_bigpost();
}
{
    $HTTP_VER = "1.0";
    test_bigpost();
}




done_testing;
