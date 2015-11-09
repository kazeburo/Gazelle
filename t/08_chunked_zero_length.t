use strict;
use HTTP::Request;
use Test::More;
use t::TestUtils;


$Plack::Test::Impl = "Server";
$ENV{PLACK_SERVER} = 'Gazelle';


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
        local $t::TestUtils::HTTP_VER = "1.1";
        my $req = HTTP::Request->new(GET => "http://localhost/");
        my $res = $cb->($req);
        is $res->content, "ContentAgain0";

        local $t::TestUtils::HTTP_VER = "1.0";
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
        local $t::TestUtils::HTTP_VER = "1.1";
        my $req = HTTP::Request->new(GET => "http://localhost/");
        my $res = $cb->($req);
        is $res->status_line, "200 OK";
        is $res->content, "ContentAgain0";

        local $t::TestUtils::HTTP_VER = "1.0";
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
        local $t::TestUtils::HTTP_VER = "1.1";
        my $req = HTTP::Request->new(GET => "http://localhost/");
        my $res = $cb->($req);
        is $res->content, "";

        local $t::TestUtils::HTTP_VER = "1.0";
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
        local $t::TestUtils::HTTP_VER = "1.1";
        my $req = HTTP::Request->new(GET => "http://localhost/");
        my $res = $cb->($req);
        is $res->content, "";
        local $t::TestUtils::HTTP_VER = "1.0";
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
        local $t::TestUtils::HTTP_VER = "1.1";
        my $req = HTTP::Request->new(GET => "http://localhost/");
        my $res = $cb->($req);
        is $res->status_line, "200 OK";
        is $res->content, "ContentAgain0";
        local $t::TestUtils::HTTP_VER = "1.0";
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
        local $t::TestUtils::HTTP_VER = "1.1";
        my $req = HTTP::Request->new(GET => "http://localhost/");
        my $res = $cb->($req);
        is $res->content, "";
        local $t::TestUtils::HTTP_VER = "1.0";
        $req = HTTP::Request->new(GET => "http://localhost/");
        $res = $cb->($req);
        is $res->content, "";
    };
}


done_testing;
