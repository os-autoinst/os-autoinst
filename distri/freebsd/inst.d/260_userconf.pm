use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle;
	sendkey "ret";	# manage users
	sendkey "u";	# add user
	sleep 2;
	sendkey "ret";
	sendautotype "$username\t\t\t";
	sendautotype "$password\t";
	sendautotype "$password\t";
	sendautotype(("\b" x 7).$realname."\t");
	sendautotype "wheel\t"; # groups
	sendautotype "\t" x 2; # skip homedir and shell
	sleep 3;
	sendkey "ret";	# done with user details
	sendkey "x";	# exit
	sendkey "ret";
	sleep 3;


	sendkey "ret"; # root user helptext
	sendautotype "$password\n";
	sendautotype "$password\n";
	sleep 2;
	sendkey "ret";	# config menu
	sleep 2;
	sendkey "x";	# exit install menu
	sleep 2;
	sendkey "tab";	# tab confirm exit & reboot
	sendkey "ret";
	sleep 2;
	sendkey "ret";	# confirm media removal message
}

1;
