use strict;
use Test::More;
use Plack::Test::Suite;

my $HTTP_VER = "1.1";
sub HTTP::Tiny::write_request_header {
    @_ == 4 || die(q/Usage: $handle->write_request_header(method, request_uri, headers)/ . "\n");
    my ($self, $method, $request_uri, $headers) = @_;

    return $self->write_header_lines($headers, "$method $request_uri HTTP/$HTTP_VER\x0D\x0A");
}

{
    Plack::Test::Suite->run_server_tests('Gazelle');
}
sleep 1;
{
    $HTTP_VER = "1.0";
    Plack::Test::Suite->run_server_tests('Gazelle');
}


done_testing();

