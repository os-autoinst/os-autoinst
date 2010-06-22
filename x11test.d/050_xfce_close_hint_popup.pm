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
	sendkey "alt-f4"; # close hint popup
	waitidle;
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
