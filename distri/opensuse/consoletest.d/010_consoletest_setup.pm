use base "basetest";
use bmwqemu;


sub run()
{ my $self=shift;
	script_sudo("chown $username /dev/$serialdev");
	script_run("echo 010_consoletest_setup OK > /dev/$serialdev");
	# it is only a waste of time, if this does not work
	alarm 3 unless waitserial("010_consoletest_setup OK", 10);
}

1;
