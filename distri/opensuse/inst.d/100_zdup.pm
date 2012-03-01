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
	script_sudo("zypper modifyrepo --all --disable");
	if($ENV{TUMBLEWEED}) {
		script_sudo("zypper ar --refresh http://widehat.opensuse.org/distribution/openSUSE-current/repo/oss/ 'openSUSE Current OSS'");
		script_sudo("zypper ar --refresh http://widehat.opensuse.org/distribution/openSUSE-current/repo/non-oss/ 'openSUSE Current non-OSS'");
		script_sudo("zypper ar --refresh http://widehat.opensuse.org/update/openSUSE-current/ 'openSUSE Current Update'");
	}
	my $nr=1;
	foreach my $r (split(/\+/, $ENV{ZDUPREPOS})) {
		script_sudo("zypper addrepo $r repo$nr");
		$nr++;
	}
	script_sudo("zypper --gpg-auto-import-keys refresh");
	script_sudo("zypper dup -l");
	$self->take_screenshot;
	#for(1..20) { sendkeyw "3"; # ignore unresolvable
	#}
	for(1..20) {
		sendkey "2"; # ignore unresolvable
		sendkeyw "ret";
	}
	sendautotype("1\n"); # some conflicts can not be ignored
	$self->take_screenshot;
	sendautotype("y\n"); # confirm
	local $ENV{SCREENSHOTINTERVAL}=2.5;
	for(1..12) {
		sleep 60;
		sendkey "shift"; # prevent console screensaver
	}
	for(1..12) {
		waitstillimage(60,66) || sendkey "shift"; # prevent console screensaver
	}
	waitstillimage(60, 5000); # wait for upgrade to finish

	$self->take_screenshot; sleep 2;
	sendkey "ctrl-alt-f4"; sleep 3;

	sendautotype "n\n"; # don't view notifications
}

1;
