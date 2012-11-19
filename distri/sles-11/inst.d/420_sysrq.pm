use base "installstep";
use strict;
use bmwqemu;

# for locating bnc#730103

sub run()
{ my $self=shift;
	sendkey "ctrl-alt-f2"; sleep 4;
	sendautotype "echo 'ENABLE_SYSRQ=\"1\"' >> /etc/sysconfig/sysctl\n";
	sendautotype "echo 1 > /proc/sys/kernel/sysrq\n";
	sendkey "alt-sysrq-9"; # enable verbose backtraces
	script_run("dmesg|tail");
	sendkey "ctrl-alt-f7"; sleep 4;
}

1;
