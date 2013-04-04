use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return($ENV{DESKTOP} eq "xfce");
}

sub run()
{
	my $self=shift;
	waitinststage "XFCE";
	sendkey "alt-c"; # close hint popup
	waitidle;
}

1;
