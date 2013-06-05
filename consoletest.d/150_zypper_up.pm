use base "basetest";
use bmwqemu;
sub run()
{
	my $self=shift;

	# Killall is used here, make sure that is installed
	script_sudo("zypper -n -q in psmisc");

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

sub checklist()
{
	# return hashref:
	return {qw(
		62ba0ecc2c42cdfa091a703e0396bebf OK
		65e3634bd721ba2b8f6779f6e4a114f5 OK
		339834b0bf1b16731ce5dc8f54eb3f25 OK
		2f361154e9f5a2fdabc0c418c44c333f OK
		c3eb48da7f9cc3d7c4665ea9372d9eb3 OK
		2b67545d6c1342df9a66b73d3d442235 OK
		92a719b6f9e894e365922262faa4b6dc OK
		8b47eaf50420e34ce2ec285c98095420 OK
		d1ec72e7741e33bc6c666e97fa8de01e fail
		e6edd4e984e590e493c16c975050e739 fail
		2ef2836eb87fd428e1de476c568c9b93 fail
	)}
}

1;
