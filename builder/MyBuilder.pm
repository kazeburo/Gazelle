package builder::MyBuilder;

use strict;
use warnings;
use parent qw(Module::Build);

sub new {
    my $self = shift;
    if ($^O eq 'freebsd' || $^O eq 'solaris') {
        print "This module does not support FreeBSD and Solaris.\n";
        exit 0;
    }
    $self->SUPER::new(@_);
}


1;
