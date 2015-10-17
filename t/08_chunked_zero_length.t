use strict;
use Test::TCP;
use Plack::Test qw//;
use HTTP::Request;
use Test::More;

my $HTTP_VER = "1.1";
sub HTTP::Tiny::write_request_header {
    @_ == 4 || die(q/Usage: $handle->write_request_header(method, request_uri, headers)/ . "\n");
    my ($self, $method, $request_uri, $headers) = @_;

    return $self->write_header_lines($headers, "$method $request_uri HTTP/$HTTP_VER\x0D\x0A");
}

$Plack::Test::Impl = "Server";
$ENV{PLACK_SERVER} = 'Gazelle';

sub test_psgi {
  Plack::Test::test_psgi(@_);
  #select undef, undef, undef, 1;
}

{
    my $app = sub {
        my $env = shift;
        return sub {
            my $response = shift;
            my $writer = $response->([ 200, [ 'Content-Type', 'text/plain' ]]);
            $writer->write("Content");
            $writer->write("");
            $writer->write("Again");
            $writer->write(undef);
            $writer->write(0);
            $writer->close;
        }
    };
    test_psgi $app, sub {
        my $cb = shift;
        my $req = HTTP::Request->new(GET => "http://localhost/");
        my $res = $cb->($req);
        is $res->content, "ContentAgain0";

        $HTTP_VER = "1.0";
        $req = HTTP::Request->new(GET => "http://localhost/");
        $res = $cb->($req);
        is $res->content, "ContentAgain0";
    };

}


{
    my $app = sub {
        my $env = shift;
        return sub {
            my $response = shift;
            my $writer = $response->([ 200, [ 'Content-Type', 'text/plain' ], ["Content","","Again",undef,0]]);
        }
    };
    test_psgi $app, sub {
        my $cb = shift;
        my $req = HTTP::Request->new(GET => "http://localhost/");
        my $res = $cb->($req);
        is $res->status_line, "200 OK";
        is $res->content, "ContentAgain0";

        $HTTP_VER = "1.0";
        $req = HTTP::Request->new(GET => "http://localhost/");
        $res = $cb->($req);
        is $res->status_line, "200 OK";
        is $res->content, "ContentAgain0";
    };
}

{
    my $app = sub {
        my $env = shift;
        return sub {
            my $response = shift;
            my $writer = $response->([ 200, [ 'Content-Type', 'text/plain' ]]);
            $writer->close;
        }
    };
    test_psgi $app, sub {
        my $cb = shift;
        my $req = HTTP::Request->new(GET => "http://localhost/");
        my $res = $cb->($req);
        is $res->content, "";
        $HTTP_VER = "1.0";
        $req = HTTP::Request->new(GET => "http://localhost/");
        $res = $cb->($req);
        is $res->content, "";
    };

}

{
    my $app = sub {
        my $env = shift;
        return sub {
            my $response = shift;
            my $writer = $response->([ 200, [ 'Content-Type', 'text/plain' ], []]);
        }
    };
    test_psgi $app, sub {
        my $cb = shift;
        my $req = HTTP::Request->new(GET => "http://localhost/");
        my $res = $cb->($req);
        is $res->content, "";
        $HTTP_VER = "1.0";
        $req = HTTP::Request->new(GET => "http://localhost/");
        $res = $cb->($req);
        is $res->content, "";
    };
}

{
    my $app = sub {
        my $env = shift;
        [ 200, [ 'Content-Type', 'text/plain' ], ["Content","","Again",undef,0]];
    };
    test_psgi $app, sub {
        my $cb = shift;
        my $req = HTTP::Request->new(GET => "http://localhost/");
        my $res = $cb->($req);
        is $res->status_line, "200 OK";
        is $res->content, "ContentAgain0";
        $HTTP_VER = "1.0";
        $req = HTTP::Request->new(GET => "http://localhost/");
        $res = $cb->($req);
        is $res->status_line, "200 OK";
        is $res->content, "ContentAgain0";
    };
}
{
    my $app = sub {
        my $env = shift;
        [ 200, [ 'Content-Type', 'text/plain' ], []];
    };
    test_psgi $app, sub {
        my $cb = shift;
        my $req = HTTP::Request->new(GET => "http://localhost/");
        my $res = $cb->($req);
        is $res->content, "";
        $HTTP_VER = "1.0";
        $req = HTTP::Request->new(GET => "http://localhost/");
        $res = $cb->($req);
        is $res->content, "";
    };
}


done_testing;
