use base "basetest";
use strict;
use bmwqemu;

sub is_applicable
{
	if($::install_after_partitioning) {return $ENV{NETINST}}
	else {return !$ENV{NETINST}}
}

sub run()
{
	my $self=shift;
	{
		local $ENV{SCREENSHOTINTERVAL}=5;
		waitstillimage(25, 600);
	}
	sendautotype "g\n"; # Configure the package manager (country=Germany)
	$self->take_screenshot; sleep 2;
	sendkey "ret"; # use first mirror
	if($ENV{HTTPPROXY}) {
		# this needs qemu>=0.13 for colons or
		# http://www.mail-archive.com/qemu-devel@nongnu.org/msg34190.htm
		sendautotype "http://$ENV{HTTPPROXY}/"; # proxy
	}
	$self->take_screenshot; sleep 2;
	sendkey "ret"; # default: no proxy
}

1;
