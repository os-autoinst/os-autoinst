package basenoupdate;
use base "basetest";

sub is_applicable()
{
	return not $ENV{UPGRADE};
}

1;
