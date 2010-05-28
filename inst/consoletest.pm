#!/usr/bin/perl -w
use strict;
use bmwqemu;

# start console application
sub script_run($;$)
{ my $name=shift; my $wait=shift;
	waitidle;
	sendautotype("$name\n");
	waitidle $wait;
	sleep 3;
}

my $sudos=0;
sub script_sudo($;$)
{ my ($prog,$wait)=@_;
	sendautotype("sudo $prog\n");
	if(!$sudos++) {
		sleep 1;
		sendautotype "$password\n";
	}
	waitidle $wait;
}

sub clear_console()
{
	sendkey "ctrl-c";
	sleep 1;
	sendkey "ctrl-c";
	sendautotype "reset\n";
	sleep 2;
}


# init
# log into text console
sendkey "ctrl-alt-f2";
sleep 2;
sendautotype "$username\n";
sleep 1;
sendautotype "$password\n";
sleep 3;
sendautotype "PS1=\$\n"; # set constant shell promt
#sendautotype 'PS1=\$\ '."\n"; # qemu-0.12.4 can not do backslash yet. http://permalink.gmane.org/gmane.comp.emulators.qemu/71856


for my $script (<$scriptdir/consoletest.d/*.pm>) {
	clear_console; # clear screen for easier automated testing for success
	diag "starting $script";
	do $script;
	if($@) {diag "$script failed with $@";}
	else {diag "$script done";}
	sleep 2;
}

# cleanup
sleep 2;
sendkey "ctrl-d"; # logout
sleep 2;

sendkey "ctrl-alt-f7"; # go back to X11
sleep 2;

1;
