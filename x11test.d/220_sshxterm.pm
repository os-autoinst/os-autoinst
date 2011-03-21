use base "basetest";
use bmwqemu;

sub is_applicable
{
	return !$ENV{NICEVIDEO} && !$ENV{LIVETEST};
}

sub run()
{
	my $self=shift;
	mousemove_raw(31000, 31000); # move mouse off screen again
	x11_start_program("xterm");
	script_run("ssh -XC root\@localhost xterm");
	sendautotype("yes\n"); sleep 2;
	sendautotype("$password\n");
	sleep 2;
	for(1..13) { sendkey "ret" }
	sendautotype("echo If you can see this text, ssh-X-forwarding  is working.\n");
	sleep 2;
	$self->take_screenshot;
	sendkey "alt-f4"; sleep 1;
	sendkey "alt-f4"; sleep 2;
}

sub checklist()
{
	# return hashref:
	return {qw(
		aa0c8f8f444fadc2ad42546ec61367da OK
		9fec86c6b297ba15c6cbf83b24572035 OK
		538027916196b24796b459be204930d9 OK
		242a185e08c0cc2530d242b96c365485 OK
		4e9d3a812194027fd1e6756cd1596544 OK
		aec996193177db673fabede569fbe1d6 OK
		86d83eb89715bf9450f691eb1f583193 OK
	)}
}

1;
