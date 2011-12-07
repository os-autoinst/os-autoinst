use base "basetest";
use bmwqemu;

sub is_applicable
{
	return !$ENV{NETINST};
}

sub run()
{ my $self=shift;
	script_run("dhcpcd");
	sleep 20;
	script_run "echo 'Server = http://ftp5.gwdg.de/pub/linux/archlinux/\$repo/os/\$arch' >> /etc/pacman.d/mirrorlist";
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
