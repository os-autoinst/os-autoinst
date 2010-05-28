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
}


# init
# log into text console
sendkey "ctrl-alt-f2";
sleep 2;
sendautotype "$username\n";
sleep 1;
sendautotype "$password\n";


for my $script (<$scriptdir/consoletest.d/*.pm>) {
	diag "starting $script";
	do $script;
	if($@) {diag "$script failed with $@";}
	else {diag "$script done";}
	sleep 2;
	clear_console; # clear screen for easier automated testing for success
}

# cleanup
sleep 2;
sendkey "ctrl-d"; # logout
sleep 2;

sendkey "ctrl-alt-f7"; # go back to X11
sleep 2;

1;
