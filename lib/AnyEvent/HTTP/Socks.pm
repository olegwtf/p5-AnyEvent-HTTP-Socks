package AnyEvent::HTTP::Socks;

use strict;
use Socket;
use IO::Socket::Socks;
use AnyEvent::Socket;
use Errno;
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

my $socks_regex = qr!^socks(4|4a|5)://(?:([^:]+):([^@]*)@)?([^:]+):(\d+)$!;

sub http_get($@) {
	my ($url, $cb) = (shift, pop);
	my %opts = @_;
	
	my $socks = delete $opts{socks};
	if ($socks) {
		if (my ($s_ver, $s_login, $s_pass, $s_host, $s_port) = $socks =~ $socks_regex) {
			$opts{tcp_connect} = sub {
				_socks_prepare_connection($s_ver, $s_login, $s_pass, $s_host, $s_port, @_);
			};
		}
		else {
			croak 'unsupported socks address specified';
		}
	}
	
	AnyEvent::HTTP::http_get($url, %opts, $cb);
}

sub http_head($@) {
	my ($url, $cb) = (shift, pop);
	my %opts = @_;
	
	my $socks = delete $opts{socks};
	if ($socks and my ($s_ver, $s_login, $s_pass, $s_host, $s_port) = $socks =~ $socks_regex) {
		$opts{tcp_connect} = sub {
			_socks_prepare_connection($s_ver, $s_login, $s_pass, $s_host, $s_port, @_);
		};
	}
	
	AnyEvent::HTTP::http_head($url, %opts, $cb);
}

sub http_post($$@) {
	my ($url, $body, $cb) = (shift, shift, pop);
	my %opts = @_;
	
	my $socks = delete $opts{socks};
	if ($socks and my ($s_ver, $s_login, $s_pass, $s_host, $s_port) = $socks =~ $socks_regex) {
		$opts{tcp_connect} = sub {
			_socks_prepare_connection($s_ver, $s_login, $s_pass, $s_host, $s_port, @_);
		};
	}
	
	AnyEvent::HTTP::http_post($url, $body, %opts, $cb);
}

sub http_request($$@) {
	my ($method, $url, $cb) = (shift, shift, pop);
	my %opts = @_;
	
	my $socks = delete $opts{socks};
	if ($socks and my ($s_ver, $s_login, $s_pass, $s_host, $s_port) = $socks =~ $socks_regex) {
		$opts{tcp_connect} = sub {
			_socks_prepare_connection($s_ver, $s_login, $s_pass, $s_host, $s_port, @_);
		};
	}
	
	AnyEvent::HTTP::http_request($method, $url, %opts, $cb);
}

sub _socks_prepare_connection {
	my ($s_ver, $s_login, $s_pass, $s_host, $s_port, $c_host, $c_port, $c_cb, $p_cb) = @_;
	
	socket(my $sock, PF_INET, SOCK_STREAM, getprotobyname('tcp'))
		or return $c_cb->();
	my $timeout = $p_cb->($sock);
	
	my ($watcher, $timer);
	my $cv = AE::cv {
		_socks_connect(\$watcher, \$timer, $sock, $s_ver, $s_login, $s_pass, $s_host, $s_port, $c_host, $c_port, $c_cb);
	};
	
	$cv->begin;
	
	$cv->begin;
	inet_aton $s_host, sub {
		$s_host = format_address shift;
		$cv->end if $cv;
	};
	#                                                                 '4a' == 4 -> true
	if (($s_ver == 5 &&  $IO::Socket::Socks::SOCKS5_RESOLVE == 0) || ($s_ver eq '4' && $IO::Socket::Socks::SOCKS4_RESOLVE == 0)) {
		# resolving on client side enabled
		$cv->begin;
		inet_aton $c_host, sub {
			$c_host = format_address shift;
			$cv->end if $cv;
		}
	}
	
	$cv->end;
	
	$timer = AnyEvent->timer(
		after => $timeout,
		cb => sub {
			undef $watcher;
			undef $cv;
			$! = Errno::ETIMEDOUT;
			$c_cb->();
		}
	);
	
	return $sock;
}

sub _socks_connect {
	my ($watcher, $timer, $sock, $s_ver, $s_login, $s_pass, $s_host, $s_port, $c_host, $c_port, $c_cb) = @_;
	
	my @specopts;
	if ($s_ver eq '4a') {
		$s_ver = 4;
		push @specopts, SocksResolve => 1;
	}
	
	if (defined $s_login) {
		push @specopts, Username => $s_login, Password => $s_pass;
		if ($s_ver == 5) {
			push @specopts, AuthType => 'userpass';
		}
	}
	
	my $sock = IO::Socket::Socks->new_from_socket(
		$sock,
		Blocking     => 0,
		ProxyAddr    => $s_host,
		ProxyPort    => $s_port,
		SocksVersion => $s_ver||5,
		ConnectAddr  => $c_host,
		ConnectPort  => $c_port,
		@specopts
	) or return $c_cb->();
	
	$$watcher = AnyEvent->io(
		fh => $sock,
		poll => 'w',
		cb => sub { _socks_handshake($watcher, $timer, WRITE_WATCHER, $sock, $c_cb) }
	);
}

sub _socks_handshake {
	my ($watcher, $timer, $w_type, $sock, $c_cb) = @_;
	
	if ($sock->ready) {
		undef $$watcher;
		undef $$timer;
		return $c_cb->($sock);
	}
	
	if ($SOCKS_ERROR == SOCKS_WANT_WRITE) {
		if ($w_type != WRITE_WATCHER) {
			undef $$watcher;
			$$watcher = AnyEvent->io(
				fh => $sock,
				poll => 'w',
				cb => sub { _socks_handshake($watcher, $timer, WRITE_WATCHER, $sock, $c_cb) }
			);
		}
	}
	elsif ($SOCKS_ERROR == SOCKS_WANT_READ) {
		if ($w_type != READ_WATCHER) {
			undef $$watcher;
			$$watcher = AnyEvent->io(
				fh => $sock,
				poll => 'r',
				cb => sub { _socks_handshake($watcher, $timer, READ_WATCHER, $sock, $c_cb) }
			);
		}
	}
	else {
		# unknown error
		$@ = "IO::Socket::Socks: $SOCKS_ERROR";
		undef $$watcher;
		undef $$timer;
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
