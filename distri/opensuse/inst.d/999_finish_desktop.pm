use base "basetest";
use bmwqemu;

# using this as base class means only run when an install is needed
sub is_applicable()
{
	my $self=shift;
	return $self->SUPER::is_applicable && $ENV{LIVETEST};
}

sub run()
{
	my $self = shift;

	waitforneedle("desktop-at-first-boot", 60);
}

sub test_flags() {
	return { 'fatal' => 1, 'important' => 1 };
}




1;
