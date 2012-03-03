use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	waitstillimage(15,90);
	$self->take_screenshot;
	sendautotype "$password\n"; # root PW
	sendautotype "$password\n"; # root PW
	sendautotype "$realname\n"; # real name
	sendkey "ret"; # username
	sendautotype "$password\n"; # user PW
	sendautotype "$password\n"; # user PW
}

1;
