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
	$self->check_screen;
	sleep 2;
	sendkeyw "alt-a"; # accept
	sendkeyw "alt-o"; # continue (accepting dependencies)
	waitstillimage(16,60);
	script_run('echo $?');
	$self->check_screen;
	sendkey "ctrl-l"; # clear screen to see that second update does not do any more
	script_sudo("rpm -e  gvim"); # extra space to have different result images than for zypper_in test
	script_run("rpm -q gvim");
	# make sure we go out of here
	waitforneedle('test-yast2_i-gvim-not-installed', 1);
}

1;
