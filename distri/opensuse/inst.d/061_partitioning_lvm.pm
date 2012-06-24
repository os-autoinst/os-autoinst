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
		sendpassword;
		sendkey "tab";
		sendpassword;
		sendkeyw "ret";
	}
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
