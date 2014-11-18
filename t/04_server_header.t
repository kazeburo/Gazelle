use strict;
use warnings;
use Test::More;
use Test::TCP;
use LWP::UserAgent;
use Plack::Loader;

test_tcp(
    client => sub {
        my $port = shift;
        sleep 1;
        my $ua = LWP::UserAgent->new;
        my $res = $ua->get("http://localhost:$port/");
        ok( $res->is_success );
        like( scalar $res->header('Server'), qr/gazelle/ );
        unlike( scalar $res->header('Server'), qr/Hello/ );

        $res = $ua->get("http://localhost:$port/?server=1");
        ok( $res->is_success );
        unlike( scalar $res->header('Server'), qr/gazelle/ );
        like( scalar $res->header('Server'), qr/Hello/ );

    },
    server => sub {
        my $port = shift;
        my $loader = Plack::Loader->load(
            'Gazelle',
            port => $port,
            max_workers => 5,
        );
        $loader->run(sub{
            my $env = shift;
            my @headers = ('Content-Type','text/html');
            push @headers, 'Server', 'Hello' if $env->{QUERY_STRING};
            [200, \@headers, ['HELLO']];
        });
        exit;
    },
);

done_testing;
