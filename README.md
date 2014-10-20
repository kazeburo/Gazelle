# NAME

Plack::Handler::Chobi - Starlet for performance freaks

# SYNOPSIS

    $ plackup -s Chobi --port 5003 --max-reqs-per-child 50000 \
         -E production -a app.psgi

# DESCRIPTION

Plack::Handler::Chobi is a PSGI Handler.

# LICENSE

Copyright (C) Masahiro Nagano.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Masahiro Nagano <kazeburo@gmail.com>
