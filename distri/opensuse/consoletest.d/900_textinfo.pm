use base "basetest";
use strict;
use bmwqemu;

# have various useful general info included in videos
sub run()
{
	my $self=shift;
	script_run('uname -a');
#	$self->check_screen;
	script_run('df');
	sendautotype "/sbin/btrfs filesystem df /\n" if $ENV{BTRFS};
	script_run('free');
	script_run('rpm -qa kernel-*');
	script_run('grep DISPLAYMANAGER /etc/sysconfig/displaymanager');
	script_run('grep DEFAULT /etc/sysconfig/windowmanager');
	script_run("ls -l /etc/ntp*");
	script_run("du /var/log/messages");
	$self->check_screen;
	local $ENV{SCREENSHOTINTERVAL}=3; # uninteresting stuff for automatic processing:
	script_run("ps ax > /dev/$serialdev");
	script_run("systemctl --no-pager --full > /dev/$serialdev");
	script_run("rpm -qa > /dev/$serialdev");
	script_sudo("rpm -qaV > /dev/$serialdev");
	script_sudo("tar cjf /tmp/logs.tar.bz2 /var/log");
	my $name=ref($self);
	script_run("curl --form testname=$name --form upload=@/tmp/logs.tar.bz2 10.0.2.2/cgi-bin/uploadlog");
	script_run("echo 'textinfo_ok' >  /dev/ttyS0");
	waitserial('textinfo_ok', 5);

}

1;
