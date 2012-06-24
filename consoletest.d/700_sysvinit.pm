use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{SYSVINIT};
}

sub run()
{
	my $self=shift;
	script_sudo("zypper -n rm systemd-sysvinit");
	sendkey "ret";
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
