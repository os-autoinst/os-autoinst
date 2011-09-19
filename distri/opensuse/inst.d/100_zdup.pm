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
	$ENV{ZDUPREPOS}||="http://$ENV{SUSEMIRROR}/repo/oss/";
	sendkey "ctrl-l";
	script_sudo("killall gpk-update-icon packagekitd");
	if(!$ENV{TUMBLEWEED}) {
		script_sudo("zypper modifyrepo --all --disable");
	}
	my $nr=1;
	foreach my $r (split(/\+/, $ENV{ZDUPREPOS})) {
		script_sudo("zypper addrepo $r repo$nr");
		$nr++;
	}
	script_sudo("zypper --gpg-auto-import-keys dup -l");
	$self->take_screenshot;
	#for(1..20) { sendkeyw "3"; # ignore unresolvable
	#}
	for(1..20) {
		sendkey "2"; # ignore unresolvable
		sendkeyw "ret";
	}
	$self->take_screenshot;
	sendautotype("y\n"); # confirm
	local $ENV{SCREENSHOTINTERVAL}=2.5;
	for(1..12) {
		sleep 60;
		sendkey "shift"; # prevent console screensaver
	}
	waitinststage("xxxzypperfinishedxxx", 5000); # wait for standstill
}

1;
