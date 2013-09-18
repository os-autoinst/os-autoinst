use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} eq "kde";
}

sub run()
{
	my $self=shift;
	sendkey "ctrl-alt-delete"; # shutdown
	waitidle;
	sendautotype "\t";
	waitforneedle("kde-turn-off-selected", 2);
	sendautotype "\n";
	waitinststage("splashscreen", 40);
}

1;
