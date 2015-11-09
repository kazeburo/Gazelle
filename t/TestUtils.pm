package t::TestUtils;

use strict;
use warnings;
use HTTP::Tiny;
use Test::TCP;
use Plack::Test qw//;
use base qw/Exporter/;

our @EXPORT = qw/test_psgi/;

sub test_psgi {
    my $pid = fork;
    die $! unless defined $pid;
    if ( $pid == 0 ) {
      Plack::Test::test_psgi(@_);
      exit;
    }
    wait;
}

our $HTTP_VER = "1.1";
{
    no warnings 'redefine';
    sub HTTP::Tiny::Handle::write_request_header {
        @_ == 4 || die(q/Usage: $handle->write_request_header(method, request_uri, headers)/ . "\n");
        my ($self, $method, $request_uri, $headers) = @_;
        return $self->write_header_lines($headers, "$method $request_uri HTTP/$HTTP_VER\x0D\x0A");
    }
}

1;

