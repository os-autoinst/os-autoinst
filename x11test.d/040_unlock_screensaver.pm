use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} =~m/gnome|kde/;
}

sub run()
{
	my $self=shift;
	# log in
	sendkey "backspace"; sleep 5;
	sendkey "ret"; sleep 5;
	sendautotype $password."\n";
	waitidle;
}

1;
