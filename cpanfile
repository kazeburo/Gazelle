requires 'perl', '5.008001';

requires 'Plack','1.0037';
requires 'Stream::Buffered';
requires 'Parallel::Prefork', '0.18';
requires 'Server::Starter';
requires 'Try::Tiny';
requires 'Guard';

on 'configure' => sub {
    requires 'Devel::CheckCompiler', '0.04';
};

on 'test' => sub {
    requires 'Test::More', '0.98';
    requires 'Test::TCP', 2;
    requires 'HTTP::Request::Common';
    requires 'Plack::Test::Suite';
    requires 'Plack::Test';
    requires 'HTTP::Tiny', '0.058';
};

