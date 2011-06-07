use strict;
use base "basenoupdate";
use bmwqemu;

sub run()
{
	waitinststage "performinstallation";
	local $ENV{SCREENSHOTINTERVAL}=5; # fast-forward
	waitinststage "^[^p][^e][^r][^f]", 5000;
}

1;
