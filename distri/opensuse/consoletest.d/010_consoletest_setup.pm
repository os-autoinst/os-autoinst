use base "basetest";
use bmwqemu;


sub run()
{
        my $self=shift;

	# init
	# log into text console
	sendkey "ctrl-alt-f4";
	sleep 2;
	sendautotype "$username\n";
	sleep 2;
	sendpassword; sendautotype "\n";
	sleep 3;
	sendautotype "PS1=\$\n"; # set constant shell promt
	sleep 1;
	#sendautotype 'PS1=\$\ '."\n"; # qemu-0.12.4 can not do backslash yet. http://permalink.gmane.org/gmane.comp.emulators.qemu/71856

	script_sudo("chown $username /dev/$serialdev");
	script_run("echo 010_consoletest_setup OK > /dev/$serialdev");
	# it is only a waste of time, if this does not work
	alarm 3 unless waitserial("010_consoletest_setup OK", 10);
}

sub test_class() {
  return basetest::FATAL_IMPORTANT_TEST;
}

1;
