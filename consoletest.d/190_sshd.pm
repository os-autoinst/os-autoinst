use base "basetest";
use bmwqemu;
# check if sshd works
sub run()
{
	my $self=shift;
	script_sudo('/etc/init.d/sshd restart'); # will do nothing if it is already running
	$self->take_screenshot;
	sendkey("ctrl-l");
	script_run('echo $?');
	script_sudo('/etc/init.d/sshd status');
}

sub checklist()
{
	# return hashref:
	return {qw(
		369dfa49bdaeb2c74be111ddae4c75b1 OK
		f358adccd925bc86974213b4c3482b26 OK
	)}
}

1;
