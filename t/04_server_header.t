use strict;
use warnings;

use Test::More;
use Plack::Test;
use HTTP::Request::Common;

$Plack::Test::Impl = 'Server';
$ENV{PLACK_SERVER} = 'Gazelle';

test_psgi
    client => sub {
        my $cb = shift;

        my $res = $cb->(GET "/");
        ok( $res->is_success );
        like( scalar $res->header('Server'), qr/gazelle/ );
        unlike( scalar $res->header('Server'), qr/Hello/ );

        $res = $cb->(GET "/?server=>1");
        ok( $res->is_success );
        unlike( scalar $res->header('Server'), qr/gazelle/ );
        like( scalar $res->header('Server'), qr/Hello/ );
        like( scalar $res->header('Date'), qr/Fooo/ );
    },
    app => sub {
        my $env = shift;
        my @headers = ('Content-Type','text/html');
        push @headers, 'Server', 'Hello' if $env->{QUERY_STRING};
        push @headers, 'Date', 'Fooo' if $env->{QUERY_STRING};
        [200, \@headers, ['HELLO']];
    };

done_testing;
