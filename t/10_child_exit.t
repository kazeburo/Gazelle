use strict;
use warnings;

use Test::More;
use Plack::Runner;

$SIG{CONT} = sub { pass('child_exit has been executed.') };

plan tests => 1;
our $main_pid = $$;
my $pid = fork;
if ( $pid == 0 ) {
    my $runner = Plack::Runner->new;
    $runner->parse_options(
        qw(--server Gazelle --max-workers 1 --child-exit),
        "sub { kill 'CONT', $main_pid }",
    );
    $runner->run(sub{
        my $env = shift;
        [200, ['Content-Type'=>'text/html'], ["HELLO"]];
    });
    exit 0;
}

sleep 1;

kill 'TERM', $pid;
waitpid($pid, 0);

done_testing();
