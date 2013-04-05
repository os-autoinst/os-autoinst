use base "basetest";
use bmwqemu;


sub run()
{ my $self=shift;
	waitstillimage(120,1000);
	sendkey "ctrl-alt-f4";
	sleep 2;
	sendautotype "$username\n";
	waitidle;
	sleep 5;
	sendpassword;
	sendkey "ret";
	sleep 10;
	$self->take_screenshot;
	sleep 1;
	sendautotype "su -\n";
	sleep 10;
	sendpassword; 
	sendkey "ret";
	script_run("echo 010_consoletest_setup OK > /dev/$serialdev");
	# it is only a waste of time, if this does not work
	alarm 3 unless waitserial("010_consoletest_setup OK", 30);
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
