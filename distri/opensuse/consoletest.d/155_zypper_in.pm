use base "basetest";
use bmwqemu;
sub run()
{
	my $self=shift;
	script_run("zypper lr -d > /dev/$serialdev");
	script_sudo("killall gpk-update-icon kpackagekitsmarticon packagekitd");
	script_sudo("zypper ar http://download.opensuse.org/repositories/Cloud:/EC2/openSUSE_Factory/Cloud:EC2.repo"); # for suse-ami-tools
	script_sudo("zypper --gpg-auto-import-keys -n in screen rsync gvim suse-ami-tools");
	waitstillimage(12,90);
	script_run('echo $?');
	$self->check_screen;
	sendkey "ctrl-l"; # clear screen to see that second update does not do any more
	my $pkgname=(($ENV{DISTRI}=~/fedora/)?"vim-X11":"gvim");
	script_sudo("rpm -e $pkgname");
	script_run("rpm -q $pkgname");
	$self->check_screen;
}

1;
