use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return 1;
}

sub run()
{
	my $self=shift;
	script_run("cd /tmp ; wget -q openqa.opensuse.org/opensuse/tools/recentchanges2.pl");
	script_sudo("rpm -qa | perl recentchanges2.pl > /dev/ttyS0");
	waitidle(100);
}

1;
