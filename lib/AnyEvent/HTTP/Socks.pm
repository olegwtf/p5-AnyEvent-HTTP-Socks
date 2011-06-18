package AnyEvent::HTTP::Socks;

use strict;
use Socket;
use IO::Socket::Socks;
use AnyEvent::DNS;
use Carp;
use base 'Exporter';
require AnyEvent::HTTP;

our @EXPORT = qw(
	http_get
	http_head
	http_post
	http_request
);

our $VERSION = '0.01';

use constant {
	READ_WATCHER  => 1,
	WRITE_WATCHER => 2,
};

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

sub _socks_connect {
	my ($s_host, $s_port, $s_ver, $c_host, $c_port, $c_cb, $p_cb) = @_;
	
	socket(my $sock, PF_INET, SOCK_STREAM, getprotobyname('tcp'))
		or return $c_cb->();
	$p_cb->($sock);
	
	$sock = IO::Socket::Socks->new_from_socket(
		$sock,
		Blocking     => 0,
		ProxyAddr    => $s_host,
		ProxyPort    => $s_port,
		SocksVersion => $s_ver,
		ConnectAddr  => $c_host,
		ConnectPort  => $c_port
	) or return $c_cb->();
	
	my $wr; $wr = AnyEvent->io(
		fh => $sock,
		poll => 'w',
		cb => sub { _socks_handshake($wr, WRITE_WATCHER, $sock, $c_cb) }
	);
}

sub _socks_handshake {
	my ($w_type, $sock, $c_cb) = @_[1,2,3];
	
	if ($sock->ready) {
		undef $_[0]; # remove watcher
		return $c_cb->($sock);
	}
	
	if ($SOCKS_ERROR == SOCKS_WANT_WRITE) {
		if ($w_type != WRITE_WATCHER) {
			undef $_[0];
			my $wr; $wr = AnyEvent->io(
				fh => $sock,
				poll => 'w',
				cb => sub { _socks_handshake($wr, WRITE_WATCHER, $sock, $c_cb) }
			);
		}
	}
	elsif ($SOCKS_ERROR == SOCKS_WANT_READ) {
		if ($w_type != READ_WATCHER) {
			undef $_[0];
			my $rd; $rd = AnyEvent->io(
				fh => $sock,
				poll => 'r',
				cb => sub { _socks_handshake($rd, READ_WATCHER, $sock, $c_cb) }
			);
		}
	}
	else {
		# unknown error
		undef $_[0];
		$c_cb->();
	}
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
