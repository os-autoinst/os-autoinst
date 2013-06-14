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
	}
	$self->take_screenshot;
}

1;
