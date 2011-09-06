use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return 1;
}

sub run()
{
	my $self=shift;
	script_run("cd /tmp ; wget -q openqa.opensuse.org/opensuse/tools/recentchanges.pl");
	script_sudo("perl recentchanges.pl > /dev/ttyS0");
	waitidle(100);
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
