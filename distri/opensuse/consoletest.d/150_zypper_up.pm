use base "basetest";
use bmwqemu;
sub run()
{
	my $self=shift;

	# Killall is used here, make sure that is installed
	script_sudo("zypper -n -q in psmisc");

	script_sudo("killall gpk-update-icon kpackagekitsmarticon packagekitd");
	if(!$ENV{NET} && !$ENV{TUMBLEWEED} && !$ENV{EVERGREEN} && $ENV{SUSEMIRROR}) {
		# non-NET installs have only milestone repo, which might be incompatible.
		script_sudo("zypper ar http://$ENV{SUSEMIRROR}/repo/oss Factory");
	}
	script_sudo("bash", 0); # become root
        script_run("echo 'imroot' > /dev/$serialdev");
        waitserial("imroot", 5) || die "Root prompt not there";
	script_run("cd /home/bernhard"); # make sure we're in the same dir as the needle
	script_run("grep -l cd:/// /etc/zypp/repos.d/* | xargs rm -v");
	$self->take_screenshot("cdreporemoved");
	script_run("zypper -n patch -l && echo 'worked' > /dev/$serialdev");
        waitserial("worked", 700) || die "zypper failed";
        $self->check_screen("first_run"); 
	script_run("zypper -n patch -l && echo 'worked' > /dev/$serialdev"); # first one might only have installed "update-test-affects-package-manager"
	waitserial("worked", 700) || die "zypper failed";
        $self->check_screen("second_run");
	script_run("rpm -q libzypp zypper", 0);
	checkneedle("rpm-q-libzypp", 5);
	sendkey "ctrl-l"; # clear screen to see that second update does not do any more
	script_run("zypper -n -q patch", 0);
	checkneedle("zypper-patch-3", 30);
	script_run('echo $?');
	script_run('exit');
}

sub test_flags() {
	return {'milestone' => 1};
}

1;
