use base "basetest";
use bmwqemu;
sub run()
{
	my $self=shift;
	script_run("zypper lr -d > /dev/$serialdev");
	script_sudo("killall gpk-update-icon kpackagekitsmarticon packagekitd");
	script_sudo("zypper ar http://download.opensuse.org/repositories/Virtualization:/Cloud:/EC2/openSUSE_Factory/Virtualization:Cloud:EC2.repo"); # for suse-ami-tools
	script_sudo("zypper --gpg-auto-import-keys -n in screen rsync gvim suse-ami-tools");
	waitstillimage(12,90);
	script_run('echo $?');
	$self->take_screenshot;
	sendkey "ctrl-l"; # clear screen to see that second update does not do any more
	my $pkgname=(($ENV{DISTRI}=~/fedora/)?"vim-X11":"gvim");
	script_sudo("rpm -e $pkgname");
	script_run("rpm -q $pkgname");
}

sub checklist()
{
	# return hashref:
	return {qw(
		c791dbef555ddc3b9bcc11fc42fcea74 OK
		34a442bdb544f972768a48202154d9ac OK
		c24cb6959f0b3a4f580c7c016bc65d4d OK
		5eb009baa175e28e7d68cbaddbff04a4 OK
		390ecdd22e5f3ea7743cdb93b9e7e8fc OK
		e67148abe58c658816fe21e1df412dcb OK
		5b4666e8c3cca40dce122b42f7b4a5de OK
		d0496f02d19cd22df4aa2d5119b6a8b6 OK
		bf434c1b28f4b9ee004506f0faefeb38 fail
	)}
}

1;
