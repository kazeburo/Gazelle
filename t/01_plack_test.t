use strict;
use Test::More;
use Plack::Test::Suite;

Plack::Test::Suite->run_server_tests('Gazelle');
done_testing();

