use base "basetest";
use strict;
use bmwqemu;

sub is_applicable()
{
	return $ENV{ZDUP};
}

sub run()
{
	my $self=shift;
	sendkey "ctrl-l";
	script_sudo("killall gpk-update-icon packagekitd");
	script_sudo("zypper modifyrepo --all --disable");
	script_sudo("zypper addrepo http://$ENV{SUSEMIRROR}/repo/oss/ newoss");
	script_sudo("zypper dup -l");
	$self->take_screenshot;
	#for(1..20) { sendkeyw "3"; # ignore unresolvable
	#}
	for(1..20) {
		sendkey "2"; # ignore unresolvable
		sendkeyw "ret";
	}
	$self->take_screenshot;
	sendautotype("y\n"); # confirm
	local $ENV{SCREENSHOTINTERVAL}=5;
	for(1..12) {
		sleep 60;
		sendkey "shift"; # prevent console screensaver
	}
	waitinststage("xxxzypperfinishedxxx", 5000); # wait for standstill
}

1;
