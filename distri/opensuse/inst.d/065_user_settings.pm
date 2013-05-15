#!/usr/bin/perl -w
use strict;
use base "basenoupdate";
use bmwqemu;

sub run()
{
	my $self=shift;
	# user setup
	waitforneedle("inst-usersetup", 5);
	sendautotype($realname);
	sendkey "tab";
	#sleep 1;
	sendkey "tab";
	for(1..2) {
		sendautotype("$password\t");
	}
	waitforneedle("inst-userinfostyped", 5);
	if($ENV{NOAUTOLOGIN}) {
		sendkey $cmd{"noautologin"};
		waitforneedle("autologindisabled", 5);
	}
	if($ENV{DOCRUN}) {
		sendkey $cmd{"otherrootpw"};
		waitforneedle("rootpwdisabled", 5);
	}
	# done user setup
	sendkey $cmd{"next"};
	# loading cracklib
	waitforneedle("inst-userpasswdtoosimple", 6);
	sendkey "ret";
	#sleep 1;
	# PW too easy (only chars)
	#sendkey "ret";
	if($ENV{DOCRUN}) { # root user
		waitidle;
		for(1..2) {
			sendautotype("$password\t");
			sleep 1;
		}
		$self->check_screen;
		sendkey $cmd{"next"};
		# loading cracklib
		waitidle 6;
		# PW too easy (cracklib)
		sendkey "ret";
		waitidle;
	}
}

1;
