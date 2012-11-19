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

	# Register against SMT
	script_run("wget http://smt.suse.de/repo/tools/clientSetup4SMT.sh; chmod +x clientSetup4SMT.sh");
	script_sudo("./clientSetup4SMT.sh --host smt.suse.de");
	sleep 5;
	sendautotype "y\n";
	sleep 5;
	sendautotype "y\n";
	waitstillimage(27, 200);
	script_run("rm ./clientSetup4SMT.sh");
}

1;
