requires 'perl', '5.008001';

requires 'Plack';
requires 'Stream::Buffered';
requires 'Parallel::Prefork';
requires 'Server::Starter';
requires 'Try::Tiny';
requires 'Time::HiRes';
requires 'Guard';

on 'test' => sub {
    requires 'Test::More', '0.98';
    requires 'HTTP::Request::Common';
    requires 'Plack::Test::Suite';
    requires 'Plack::Test';
};

