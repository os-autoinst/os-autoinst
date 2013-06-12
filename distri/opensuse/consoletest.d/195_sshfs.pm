use base "basetest";
use bmwqemu;
sub run()
{
	my $self=shift;
	become_root();
	script_run("killall gpk-update-icon kpackagekitsmarticon packagekitd");
	script_run("zypper -n in sshfs");
	waitstillimage(12,90);
	script_run('cd /var/tmp ; mkdir mnt ; sshfs localhost:/ mnt');
	sendautotype("yes\n"); # trust ssh host key
	sendpassword;
	sendkey "ret";
	waitforneedle('sshfs-accepted', 3);
	script_run('cd mnt/tmp');
	script_run("zypper -n in gvim");
	script_run("rpm -e gvim");
	script_run('cd /tmp');
	# become user again
	script_run('exit');
	$self->check_screen;
}

1;
