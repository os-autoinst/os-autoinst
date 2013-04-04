use base "basetest";
use bmwqemu;


sub run()
{ my $self=shift;
	waitidle;
	sendkey "ctrl-alt-f4";
	sleep 2;
	script_sudo("tail -20 /var/log/messages > /dev/$serialdev");
	script_sudo("/sbin/halt");
}

1;
