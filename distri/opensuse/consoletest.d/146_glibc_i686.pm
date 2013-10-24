use base "basetest";
use bmwqemu;

sub run()
{
	my $self=shift;
	script_sudo("zypper ref");
	script_run("clear");
	script_run("echo 'Checking whether we have i686 binary, we should have...'; zypper se -s glibc | grep i686; echo glibc_finished > /dev/$serialdev");
	waitserial('glibc_finished', 300);
	$self->check_screen;
}

1;
