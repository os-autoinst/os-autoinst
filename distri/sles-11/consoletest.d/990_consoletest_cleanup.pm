use base "basetest";
use bmwqemu;


sub run()
{ my $self=shift;
	sendkeyw "ctrl-alt-f7";
	sleep 4;
}

1;
