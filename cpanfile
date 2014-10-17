
requires 'perl', '5.008001';

requires 'Plack';
requires 'HTTP::Parser::XS';
requires 'Stream::Buffered';
requires 'Parallel::Prefork';
requires 'Server::Starter';
requires 'AnyEvent';
requires 'Try::Tiny';
requires 'Time::HiRes';

on 'test' => sub {
    requires 'Test::More', '0.98';
};

