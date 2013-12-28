use base "basetest";
use bmwqemu;


sub run()
{ my $self=shift;
	waitidle(120);
	sleep 10;
	waitidle(30);
	if($ENV{DESKTOP}=~/none/) {
		waitinststage("mageia4-text-console",3000);
        } else {
		waitstillimage(20,1000);
		sendkey "ctrl-alt-f4";
	}
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
	sleep 10;
	script_run("echo 010_consoletest_setup OK > /dev/$serialdev");
	# it is only a waste of time, if this does not work
	alarm 3 unless waitserial("010_consoletest_setup OK", 30);
}

sub checklist()
{
	# return hashref:
	return {qw(
		e6e7376c102f29f8b8bec9845107d146 OK
		2d151f911ab9a69a9fb165b2295546da OK
		8fb20758ca5a032c6186ba0651effadc OK
	)}
}

1;
