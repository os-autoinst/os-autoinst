use strict;
use base "installstep";
use bmwqemu;

sub is_applicable()
{
	my $self=shift;
	return $self->SUPER::is_applicable && !$ENV{LIVECD} && $ENV{UPGRADE};
}

sub run()
{
	my $self=shift;

	$self->check_screen;
	sendkeyw $cmd{"next"};
	waitforneedle("remove-repository", 10);
	sendkeyw $cmd{"next"};
	waitforneedle("installation-settings", 10);
}

1;
