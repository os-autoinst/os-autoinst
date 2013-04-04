use base "basetest";
use bmwqemu;


sub run()
{ my $self=shift;
	sendautotype "halt\n";
}

1;
