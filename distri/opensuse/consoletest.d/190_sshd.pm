use base "basetest";
use bmwqemu;
# check if sshd works
sub run()
{
	my $self=shift;
	script_sudo('/sbin/insserv -r SuSEfirewall2_setup'); # disable firewall to make better cloud images
	script_sudo('/sbin/insserv -r SuSEfirewall2_init');
	script_sudo('systemctl disable SuSEfirewall2');
	script_sudo('/sbin/chkconfig -a sshd');
	script_sudo('/etc/init.d/sshd restart'); # will do nothing if it is already running
	$self->check_screen;
	sendkey("ctrl-l");
	script_run('echo $?');
	script_sudo('/etc/init.d/sshd status');
	$self->check_screen;
}

1;
