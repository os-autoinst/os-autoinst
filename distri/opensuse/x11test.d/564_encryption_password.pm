use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return 0 unless $ENV{ENCRYPT};
	return !$ENV{LIVETEST} || $ENV{USBBOOT};
}

sub run()
{
	wait_encrypt_prompt;
}

1;
