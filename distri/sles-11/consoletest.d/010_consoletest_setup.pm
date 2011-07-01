use base "basetest";
use bmwqemu;


sub run()
{ my $self=shift;
	sendkey "ctrl-alt-f2";
	sleep 2;
	sendautotype "$username\n";
	sleep 2;
	sendpassword; sendautotype "\n";
	sleep 3;
	$self->take_screenshot;
	sendautotype "PS1=\$\n"; # set constant shell promt
	sleep 1;
	script_sudo("chown $username /dev/$serialdev");
	script_run("echo 010_consoletest_setup OK > /dev/$serialdev");
	# it is only a waste of time, if this does not work
	alarm 1 unless waitserial("010_consoletest_setup OK", 10);
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
