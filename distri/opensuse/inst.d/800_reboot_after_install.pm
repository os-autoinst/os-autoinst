use base "basetest";
use bmwqemu;
# run all application tests after an extra reboot
# first boot is special - could have used kexec and has second stage configuration
sub is_applicable()
{
	return 0 if $ENV{LIVETEST};
	return 0 if $ENV{NICEVIDEO};
	return 1 if $ENV{DESKTOP} eq "kde" && !$ENV{UPGRADE}; # FIXME workaround https://bugzilla.novell.com/show_bug.cgi?id=804143
	return $ENV{REBOOTAFTERINSTALL} && !$ENV{UPGRADE};
}

sub run()
{
	my $self=shift;
	sendkey "ctrl-alt-f3";
	sleep 4;
	qemusend "eject ide1-cd0";
	sendkey "ctrl-alt-delete";

	wait_encrypt_prompt;
	waitforneedle("reboot_after_install", 100);
}

1;
