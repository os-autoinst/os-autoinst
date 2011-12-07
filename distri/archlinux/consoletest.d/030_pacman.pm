use base "basetest";
use bmwqemu;


sub run()
{ my $self=shift;
	sendautotype "export http_proxy=http://$ENV{HTTPPROXY}/\n" if $ENV{HTTPPROXY};
	script_run "pacman -Sy";
	waitstillimage;
	sendautotype "pacman --noconfirm -S extra/alsa-utils\n";
	waitstillimage;
	if(!$ENV{NETINST}) {
		sendautotype "pacman --noconfirm -S curl\n";
		waitstillimage;
	}
	sendautotype "pacman --noconfirm -S extra/alsa-utils && echo SUCCESS\n";
	waitstillimage;
	waitidle;
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
