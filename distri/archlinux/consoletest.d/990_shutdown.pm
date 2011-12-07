use base "basetest";
use bmwqemu;


sub run()
{ my $self=shift;
	sendautotype "halt\n";
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
