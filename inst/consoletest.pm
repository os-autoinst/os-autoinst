#!/usr/bin/perl -w
use strict;
use bmwqemu;
use autotest;



if(!$ENV{NICEVIDEO}) {
# init
# log into text console
sendkey "ctrl-alt-f4";
sleep 2;
sendautotype "$username\n";
sleep 2;
sendpassword; sendautotype "\n";
sleep 3;
sendautotype "PS1=\$\n"; # set constant shell promt
sleep 1;
#sendautotype 'PS1=\$\ '."\n"; # qemu-0.12.4 can not do backslash yet. http://permalink.gmane.org/gmane.comp.emulators.qemu/71856

sub consoletestrunfunc
{
	my($test)=@_;
	my $class=ref $test;
	clear_console; # clear screen to make screen content independent from previous tests
	diag "starting $class";
	bmwqemu::set_current_test($test);
	$test->run();
	bmwqemu::set_current_test(undef);
	$test->check_screen;
	diag "finished $class";
}


autotest::runtestdir("$scriptdir/consoletest.d", \&consoletestrunfunc);


# cleanup
script_sudo_logout;
sleep 2;
sendkey "ctrl-d"; # logout
sleep 2;

sendkey "ctrl-alt-f7"; # go back to X11
sleep 2;
sendkey "backspace"; # deactivate blanking
sleep 2;
waitidle;

}
if($ENV{DESKTOP}!~/textmode|minimalx/) {
	do "inst/x11test.pm" or die $@;
}

1;
