#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;

use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Socket;
# This is the library we want to avoid, but it is OK just for testing
use Socket::MsgHdr;
use POSIX;

use cv;

cv::init();
require tinycv;

# This test sends a pipe FD and message to a child process using a UNIX socket
# and SCM_RIGHTS. Then the child writes the message to the pipe and the parent
# confirms it is correct.

socketpair(my $ask, my $bsk, AF_UNIX, SOCK_STREAM, AF_UNSPEC)
  || die "Could not make socket pair: $!";

my $pid = fork || do {
    my $msg = Socket::MsgHdr->new(buflen => 1024, controllen => 64);

    recvmsg($ask, $msg);
    shutdown($ask, 2);

    my @cmsg = $msg->cmsghdr();
    my $fd   = unpack('i', $cmsg[2]);

    POSIX::write($fd, $msg->buf(), 4)
      || die "Failed to write echo to pipe: $!";
    POSIX::close($fd);

    exit(0);
};

my ($afd, $bfd) = POSIX::pipe();
unless (defined $afd && defined $bfd) {
    die "Could not create pipe: $!";
}

ok(0 < tinycv::send_with_fd($bsk, 'echo', $bfd), 'Send file handle');
POSIX::close($bfd);
shutdown($bsk, 2);

my $buf = '';
POSIX::read($afd, $buf, 4)
  || die "Failed to read echo from pipe: $!";
ok($buf eq 'echo', "Receive echo on pipe FD we sent");
POSIX::close($afd);

wait;
ok(0 == $?, 'Child process exited cleanly');

done_testing();

1;
