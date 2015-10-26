package builder::MyBuilder;

use strict;
use warnings;
use parent qw(Module::Build);
use Devel::CheckCompiler 0.04;

sub new {
    my $self = shift;
    my %args = @_;
    if ( $^O eq 'solaris') {
        print "This module does not support Solaris.\n";
        exit 0;
    }
    
    if (check_compile(<<'...', executable => 1)) {
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <sys/socket.h>

int main(void)
{
    return accept4(0, (void*)0, (void*)0, SOCK_CLOEXEC|SOCK_NONBLOCK);
}
...
        $args{extra_compiler_flags} ||= [];
        push @{$args{extra_compiler_flags}}, '-DHAVE_ACCEPT4';
    }
    $self->SUPER::new(%args);
}


1;
