#!/usr/bin/perl -w
use strict;
use bmwqemu;
use autotest;

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


sub consoletestrunfunc
{
	my($test)=@_;
	my $class=ref $test;
	clear_console; # clear screen to make screen content independent from previous tests
	diag "starting $class";
	$test->run();
	sleep 2;
	$test->take_screenshot;
}


autotest::runtestdir("consoletest.d", \&consoletestrunfunc);


# cleanup
sleep 2;
sendkey "ctrl-d"; # logout
sleep 2;

sendkey "ctrl-alt-f7"; # go back to X11
sleep 2;

1;
