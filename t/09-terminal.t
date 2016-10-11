#!/usr/bin/perl

use 5.018;
use warnings;
use autodie;
use Test::More;
use consoles::virtio_terminal;
use English qw( -no_match_vars );
use testapi ();

our $VERSION;

# Set this to an amount greater than any chunk of data sent in a unit test
my $largest_data_length = 4096;
my $login_prompt_data = <<'FIN.';


Welcome to SUSE Linux Enterprise Server 12 SP2 RC3 (x86_64) - Kernel 4.4.21-65-default (hvc0).


linux-5rw7 login: 
FIN.
my $user_name_data = "root\n";
my $password_prompt_data = 'Password: ';
my $password_data = "$testapi::password\n";
# Contains some ANSI/XTERM escape sequences
my $first_prompt_data = "\e[1mlinux-5rw7:~ #\e[0m\e(B";
my $set_prompt_data = qq/PS1="# "\n/;
my $normalised_prompt_data = '# ';

sub try_write {
    my ($fd, $msg) = @_;

    syswrite($fd, $msg)
      || die "fake_terminal: Failed to write to socket $ERRNO";
}

sub try_read {
    my ($fd) = @_;
    my ($buf, $text);

  READ: {
        sysread($fd, my $buf, $largest_data_length) || do {
            if ($ERRNO{EINTR}) {
                $text .= $buf;
                next READ;
            }
            die "fake_terminal: Could not read from socket: $ERRNO";
        };
    }
    return $buf;
}

sub fake_terminal {
    my ($sock_path) = @_;
    socket( my $listen_fd, PF_UNIX, SOCK_STREAM, 0 );
      || die "fake_terminal: Could not create socket: $ERRNO";
    bind( $listen_fd, sockaddr_un($sock_path) )
      || die "fake_terminal: Could not bind socket to path $sock_path: $ERRNO";
    listen( $listen_fd, 1 )
      || die "fake_terminal: Could not list on socket: $ERRNO";

  ACCEPT: {
        accept( my $fd, $listen_fd ) || do {
            if ($ERRNO{EINTR}) {
                next ACCEPT;
            }
            die "fake_terminal: Failed to accept connection: $ERRNO";
        };
    }

    try_write( $fd, $login_prompt_data );
    is( try_read($fd), 'root\n', 'Enter user name');
    try_write( $fd, $password_prompt_data );
    is( try_read($fd), $password_data, 'Enter password');
    try_write( $fd, $first_prompt_data );
    is( try_read($fd), $set_prompt_data, 'Normalise bash prompt');
    try_write( $fd, $normalised_prompt_data );
}
