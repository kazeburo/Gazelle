package t::TestUtils;

use strict;
use warnings;
use HTTP::Tiny 0.058;
use Test::TCP;
use Plack::Test qw//;
use base qw/Exporter/;

our @EXPORT = qw/test_psgi/;

sub test_psgi {
    my $pid = fork;
    die $! unless defined $pid;
    if ( $pid == 0 ) {
      if (ref $_[0] && @_ == 2) {
         @_ = (app => $_[0], client => $_[1]);
      }
      Plack::Test::test_psgi(listen => 1, @_);
      exit;
    }
    wait;
}

our $HTTP_VER = "1.1";
{
    no warnings 'redefine';
    sub HTTP::Tiny::Handle::write_request_header {
        @_ == 5 || die(q/Usage: $handle->write_request_header(method, request_uri, headers, header_case)/ . "\n");
        my ($self, $method, $request_uri, $headers, $header_case) = @_;
        return $self->write_header_lines($headers, $header_case, "$method $request_uri HTTP/$HTTP_VER\x0D\x0A");
    }
}

1;

