use strict;
use Test::More;
use Plack::Test::Suite;
use t::TestUtils qw//;

{
    Plack::Test::Suite->run_server_tests('Gazelle');
}

{
    local $t::TestUtils::HTTP_VER = "1.0";
    Plack::Test::Suite->run_server_tests('Gazelle');
}


done_testing();

