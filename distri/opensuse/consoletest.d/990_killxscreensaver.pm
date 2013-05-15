use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP}=~m/lxde|xfce/;
}

sub run()
{
	my $self=shift;
	script_run("killall xscreensaver");
}

1;
