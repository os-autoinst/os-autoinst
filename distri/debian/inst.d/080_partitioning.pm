use base "basetest";
use strict;
use bmwqemu;

sub x() {sleep 1};
sub run()
{
	my $self=shift;
	waitidle;
	sendkey "ret"; # partitioning = guided whole disk
	x; sendkey "ret"; # select first disk
	x; sendkey "ret"; # all files in one part
	x; sendkey "ret"; # finish
	$self->take_screenshot;sleep 1;
	x; sendkey "tab"; sendkey "ret"; # confirm partitioning
	$::install_after_partitioning=1;
}

1;
