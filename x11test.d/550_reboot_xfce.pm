use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} eq "xfce";
}

sub run()
{
	my $self=shift;
	waitidle;
	sendkey "alt-f4"; # open popup
	waitidle;
	sendkey "tab"; # reboot
	waitidle;
	sendkey "ret"; # confirm 
}

1;
