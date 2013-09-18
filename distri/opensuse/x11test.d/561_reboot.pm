use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return !$ENV{LIVETEST} || $ENV{USBBOOT};
}

sub run()
{
	my $self=shift;
	waitforneedle( "bootloader", 100); # wait until reboot
	if ($ENV{ENCRYPT}) {
	  wait_encrypt_prompt;
	}

	waitinststage "booted", 150; # wait until booted again
	mouse_hide(1);
}

sub test_flags() {
        return {'milestone' => 1, 'fatal' => 1};
}
1;
