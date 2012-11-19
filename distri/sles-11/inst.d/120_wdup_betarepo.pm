use base "basetest";
use strict;
use bmwqemu;

sub is_applicable()
{
	return $ENV{WDUP};
}

sub run()
{
	my $self=shift;

	# Add beta repo
	script_sudo("zypper ar -f http://beta.suse.com/private/SLE11SP1-BETA/x86_64/update/SLE-SERVER/11-SP1-BETA BETA");
}

1;
