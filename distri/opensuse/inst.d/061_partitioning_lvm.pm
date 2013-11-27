use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{LVM};
}

sub run()
{
	my $self=shift;
	sendkeyw "alt-l"; # enable LVM-based proposal
	if($ENV{ENCRYPT}) {
		sendkeyw "alt-y";
		waitforneedle("inst-encrypt-password-prompt");
		sendpassword;
		sendkey "tab";
		sendpassword;
		sendkeyw "ret";
		waitforneedle("partition-cryptlvm-summary", 3);
	} else {
		waitforneedle("partition-lvm-summary", 3);
	}
}

1;
