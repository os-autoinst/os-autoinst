package installstep;
use base "basetest";

use bmwqemu;

# using this as base class means only run when an install is needed
sub is_applicable()
{
	my $self=shift;
	return $self->SUPER::is_applicable && !$ENV{NOINSTALL} && !$ENV{LIVETEST};
}

sub test_flags() {
	return {'fatal' => 1};
}

sub post_fail_hook() {
	my $self = shift;
        my @tags = (@{needle::tags("yast-still-running")}, @{needle::tags("linuxrc-install-fail")});
	if (checkneedle(\@tags, 5)) {
		sendkey "ctrl-alt-f2";
		waitforneedle("inst-console");
		if(!$ENV{NET}) {
			sendautotype "dhcpcd eth0\n";
			sendautotype "ifconfig -a\n";
			sendautotype "cat /etc/resolv.conf\n";
		}
		sendautotype "save_y2logs /tmp/y2logs.tar.bz2\n";
		upload_logs "/tmp/y2logs.tar.bz2";
		$self->take_screenshot();
	}
}

1;
