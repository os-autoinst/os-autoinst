use base "basetest";
use bmwqemu;

sub is_applicable
{
	return !$ENV{NICEVIDEO} && !$ENV{LIVETEST};
}

sub run()
{
	my $self=shift;
	mouse_hide(1);
	x11_start_program("xterm");
	script_run("ssh -XC root\@localhost xterm");
	sendautotype("yes\n"); waitidle(6);
	sendautotype("$password\n");
	sleep 2;
	for(1..13) { sendkey "ret" }
	sendautotype "PS1=\"# \"\n";
	sendautotype("echo If you can see this text, ssh-X-forwarding  is working.\n");
	sleep 2;
	$self->check_screen;
	sendkey "alt-f4"; sleep 1;
	sendkey "alt-f4"; sleep 2;
}

1;
