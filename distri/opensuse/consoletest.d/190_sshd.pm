use base "basetest";
use bmwqemu;
# check if sshd works
sub run()
{
	my $self=shift;
	become_root();
	script_run('SuSEfirewall2 off');
	script_run('chkconfig sshd on');
	script_run('rcsshd restart'); # will do nothing if it is already running
	$self->check_screen;
	sendkey("ctrl-l");
	script_run('echo $?');
	script_run('rcsshd status');
	script_run('exit');
	$self->check_screen;
}

sub test_flags() {
   return {'milestone' => 1};
}

1;
