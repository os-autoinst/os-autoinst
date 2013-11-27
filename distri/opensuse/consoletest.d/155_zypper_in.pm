use base "basetest";
use bmwqemu;
sub run()
{
	my $self=shift;
	become_root();
	script_run("zypper lr -d > /dev/$serialdev");
	script_run("killall gpk-update-icon kpackagekitsmarticon packagekitd");
	#script_run("zypper ar http://download.opensuse.org/repositories/Cloud:/EC2/openSUSE_Factory/Cloud:EC2.repo"); # for suse-ami-tools
	script_run("zypper --gpg-auto-import-keys -n in screen rsync xdelta suse-ami-tools");
	waitstillimage(12,90);
	script_run('echo $?');
	$self->check_screen;
	sendkey "ctrl-l"; # clear screen to see that second update does not do any more
	my $pkgname="xdelta";
	script_run("rpm -e $pkgname");
	script_run("rpm -q $pkgname");
	script_run('exit');
	$self->check_screen;
}

1;
