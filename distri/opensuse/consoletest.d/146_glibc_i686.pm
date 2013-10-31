use base "basetest";
use bmwqemu;

# this part contains the steps to run this test
sub run()
{
	my $self=shift;
	script_run("clear");
	script_run("/lib/libc.so.*");
	$self->check_screen;
}

1;
