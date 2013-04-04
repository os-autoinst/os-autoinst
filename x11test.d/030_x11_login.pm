use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{NOAUTOLOGIN} || $ENV{XDMUSED};
}

sub run()
{
	my $self=shift;
	# log in
	sendautotype $username."\n";
	sleep 1;
	sendautotype $password."\n";
	waitidle;
}

1;
