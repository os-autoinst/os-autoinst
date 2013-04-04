use base "basetest";
use bmwqemu;
sub run()
{
	my $self=shift;
	script_sudo("killall gpk-update-icon kpackagekitsmarticon packagekitd");
	script_sudo("zypper -n in sshfs");
	waitstillimage(12,90);
	script_run('cd /var/tmp ; mkdir mnt ; sshfs localhost:/ mnt');
	sendautotype("yes\n"); # trust ssh host key
	sendpassword;
	sendkey "ret";
	script_run('cd mnt/tmp');
	script_sudo("zypper -n in gvim");
	script_sudo("rpm -e gvim");
	script_run('cd /tmp');
}

1;
