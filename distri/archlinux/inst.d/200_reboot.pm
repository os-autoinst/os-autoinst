use base "basenoupdate";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	sendautotype "reboot\n";
	waitstillimage(12,100);
}

1;
