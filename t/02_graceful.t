use strict;
use warnings;

use HTTP::Request::Common;
use Plack::Test;
use Test::More;

$Plack::Test::Impl = 'Server';
$ENV{PLACK_SERVER} = 'Gazelle';

test_psgi
    app => sub {
        my $env = shift;
        unless (my $pid = fork) {
            die "fork failed:$!"
                unless defined $pid;
            # child process
            sleep 1;
            kill 'TERM', getppid();
            exit 0;
        }
        sleep 5;
        return [ 200, [ 'Content-Type' => 'text/plain' ], [ "hello world" ] ];
    },
    client => sub {
        my $cb = shift;
        my $res = $cb->(GET "/");
        is $res->content, "hello world";
    };

done_testing;
