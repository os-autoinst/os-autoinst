use base "basetest";
use bmwqemu;


sub run()
{ my $self=shift;
	sendkey "ctrl-alt-f7";
	sleep 5;
}

1;
