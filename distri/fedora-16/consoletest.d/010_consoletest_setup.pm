use base "basetest";
use bmwqemu;


sub run()
{ my $self=shift;
	waitstillimage(12,100);
	sendkey "ctrl-alt-f4";
	sleep 2;
	sendautotype "$username\n";
	waitidle;
	sleep 2;
	sendpassword; sendautotype "\n";
	sleep 3;
	$self->take_screenshot;
	sendautotype "PS1=\$\n"; # set constant shell promt
	sleep 1;
	script_sudo("chown $username /dev/$serialdev");
	script_run("echo 010_consoletest_setup OK > /dev/$serialdev");
	# it is only a waste of time, if this does not work
	alarm 3 unless waitserial("010_consoletest_setup OK", 10);
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
