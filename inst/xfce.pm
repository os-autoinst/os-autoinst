use bmwqemu;

waitinststage "xdm-loginscreen";
waitidle;
sleep 5;
do "inst/consoletest.pm";

sleep 5;

#sendkey "alt-f2";
#waitidle;
#sleep 2;
#sendautotype "xterm\n";
#waitidle;
#script_run "firefox&";
#sendkey "alt-f4"; # default browser setting popup
#sleep 3;
#sendkey "alt-f4";
#waitidle;
#sendkey "ret"; # save+quit
#waitidle;
#sendkey "alt-f4"; # close xterm


# reboot
waitidle;
sendkey "alt-f4";
waitidle;
sendkey "tab";
waitidle;
sendkey "ret";
sleep 10;
my $ok=waitinststage "xdm-loginscreen", 80;
if($ok) {
	waitidle;

	# log in
	sendautotype $username."\n";
	sleep 1;
	sendautotype $password."\n";
	waitinststage "XFCE", 40;
	sleep 5;
}
qemusend "system_powerdown";

1;
