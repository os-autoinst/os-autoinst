use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return 0 unless $ENV{ENCRYPT};
	return !$ENV{LIVETEST} || $ENV{USBBOOT};
}

sub run()
{
	sendpassword();
	sendkey "ret";
}

1;
