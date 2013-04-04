use base "basetest";
use bmwqemu;
sub run()
{
	my $self=shift;
	script_sudo("killall gpk-update-icon kpackagekitsmarticon packagekitd");
	if(!$ENV{NET} && !$ENV{TUMBLEWEED} && !$ENV{EVERGREEN}) {
		# non-NET installs have only milestone repo, which might be incompatible.
		script_sudo("zypper ar http://$ENV{SUSEMIRROR}/repo/oss Factory");
	}
	script_sudo("zypper -n patch -l");
	$self->take_screenshot;
	waitidle 60;
	script_sudo("zypper -n patch -l"); # first one might only have installed "update-test-affects-package-manager"
	script_run("rpm -q libzypp zypper");
	$self->take_screenshot;
	sendkey "ctrl-l"; # clear screen to see that second update does not do any more
	script_sudo("zypper -n -q patch");
	waitidle;
	script_run('echo $?');
}

1;
