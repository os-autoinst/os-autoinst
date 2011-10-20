use base "basetest";
use bmwqemu;
sub run()
{
	my $self=shift;
	script_sudo("/sbin/yast2 -i");
	waitstillimage(16,60);
	sendautotype("gvim\n");sleep 3;
	sendkey "spc";   # select for install
	sleep 1;
	$self->take_screenshot;
	sleep 2;
	sendkeyw "alt-a"; # accept
	sendkeyw "alt-o"; # continue (accepting dependencies)
	waitstillimage(16,60);
	script_run('echo $?');
	$self->take_screenshot;
	sendkey "ctrl-l"; # clear screen to see that second update does not do any more
	script_sudo("rpm -e  gvim"); # extra space to have different result images than for zypper_in test
	script_run("rpm -q gvim");
}

sub checklist()
{
	# return hashref:
	return {qw(
		4c4c6b74c7f5e4a8960ca2688ce632e3 OK
	)}
}

1;
