package AnyEvent::HTTP::Socks;

use strict;
use IO::Socket::Socks;
use base 'Exporter';
require AnyEvent::HTTP;

our @EXPORT = qw(
	http_get
	http_head
	http_post
	http_request
);

our $VERSION = '0.01';

sub http_get {
	AnyEvent::HTTP::http_get(@_);
}

sub http_head {
	AnyEvent::HTTP::http_head(@_);
}

sub http_post {
	AnyEvent::HTTP::http_post(@_);
}

sub http_request {
	AnyEvent::HTTP::http_request(@_);
}

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

AnyEvent::HTTP::Socks - Perl extension for blah blah blah

=head1 SYNOPSIS

  use AnyEvent::HTTP::Socks;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for AnyEvent::HTTP::Socks, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head2 EXPORT

None by default.



=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Oleg G, E<lt>oleg@E<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Oleg G

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.12.3 or,
at your option, any later version of Perl 5 you may have available.


=cut
