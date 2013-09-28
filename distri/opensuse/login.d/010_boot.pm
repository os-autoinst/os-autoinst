use base "basetest";
use strict;
use bmwqemu;
use Time::HiRes qw(sleep);

sub is_applicable()
{
  return !$ENV{UEFI};
}



sub run()
{
    waitforneedle("inst-bootmenu", 30);
    sleep 2;
    sendkey "ret"; # boot

    waitforneedle("grub-opensuse-13.1",15);
    sleep 1;
    sendkey "ret";

    waitforneedle("desktop-at-first-boot", 300);
    
}

sub test_flags() {
	return {'fatal' => 1};
}

1;
