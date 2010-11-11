use base "basetest";
use bmwqemu;
sub run()
{
	my $self=shift;
	script_sudo("zypper -n patch");
	waitidle 60;
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
		d1ec72e7741e33bc6c666e97fa8de01e fail
		e6edd4e984e590e493c16c975050e739 fail
	)}
}

1;
