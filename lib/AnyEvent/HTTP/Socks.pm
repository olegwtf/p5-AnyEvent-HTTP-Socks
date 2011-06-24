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

our $VERSION = '0.02';

use constant {
	READ_WATCHER  => 1,
	WRITE_WATCHER => 2,
};

sub http_get($@) {
	unshift @_, 'GET';
	&http_request;
}

sub http_head($@) {
	unshift @_, 'HEAD';
	&http_request;
}

sub http_post($$@) {
	my $url = shift;
	unshift @_, 'POST', $url, 'body';
	&http_request;
}

sub http_request($$@) {
	my ($method, $url, $cb) = (shift, shift, pop);
	my %opts = @_;
	
	my $socks = delete $opts{socks};
	if ($socks) {
		if (my ($s_ver, $s_login, $s_pass, $s_host, $s_port) = $socks =~ m!^socks(4|4a|5)://(?:([^:]+):([^@]*)@)?([^:]+):(\d+)$!) {
			$opts{tcp_connect} = sub {
				_socks_prepare_connection($s_ver, $s_login, $s_pass, $s_host, $s_port, @_);
			};
		}
		else {
			croak 'unsupported socks address specified';
		}
	}
	
	AnyEvent::HTTP::http_request( $method, $url, %opts, $cb );
}

sub inject {
	my ($class, $where) = @_;
	$class->export($where, @EXPORT);
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
	
	$sock = IO::Socket::Socks->new_from_socket(
		$sock,
		Blocking     => 0,
		ProxyAddr    => $s_host,
		ProxyPort    => $s_port,
		SocksVersion => $s_ver,
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

=head1 NAME

AnyEvent::HTTP::Socks - Adds socks support for AnyEvent::HTTP 

=head1 SYNOPSIS

  use AnyEvent::HTTP;
  use AnyEvent::HTTP::Socks;
  
  http_get 'http://www.google.com/', socks => 'socks5://localhost:1080', sub {
      print $_[0];
  };

=head1 DESCRIPTION

This module adds new `socks' option to all http_* functions exported by AnyEvent::HTTP.
So you can specify socks proxy for HTTP requests.

This module uses IO::Socket::Socks as socks library, so any global variables like
$IO::Socket::Socks::SOCKS_DEBUG can be used to change the behavior.

Socks string structure is:

  scheme://login:password@host:port
  ^^^^^^   ^^^^^^^^^^^^^^ ^^^^ ^^^^
    1             2         3    4

1 - scheme can be one of the: socks4, socks4a, socks5

2 - "login:password@" part can be ommited if no authorization for socks proxy needed. For socks4
proxy "password" should be ommited, because this proxy type doesn't support login/password authentication,
login will be interpreted as userid.

3 - ip or hostname of the proxy server

4 - port of the proxy server

=head1 METHODS

=head2 AnyEvent::HTTP::Socks->inject('Package::Name')

Add socks support to some package based on AnyEvent::HTTP.

Example:

	use AnyEvent::HTTP;
	use AnyEvent::HTTP::Socks;
	use AnyEvent::Google::PageRank qw(rank_get);
	use strict;
	
	AnyEvent::HTTP::Socks->inject('AnyEvent::Google::PageRank');
	
	rank_get 'http://mail.com', socks => 'socks4://localhost:1080', sub {
		warn $_[0];
	};

=head1 NOTICE

You should load AnyEvent::HTTP::Socks after AnyEvent::HTTP, not before. Or simply load only AnyEvent::HTTP::Socks
and it will load AnyEvent::HTTP automatically.

=head1 SEE ALSO

L<AnyEvent::HTTP>, L<IO::Socket::Socks>

=head1 AUTHOR

Oleg G, E<lt>oleg@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Oleg G

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself

=cut
