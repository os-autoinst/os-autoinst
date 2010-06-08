use bmwqemu;

waitinststage "LXDE";
waitidle;
sleep 5;
do "inst/consoletest.pm";

sleep 5;

sendkey "alt-f2";
waitidle;
sleep 2;
sendautotype "xterm\n";
waitidle;
script_run "firefox&";
sendkey "alt-f4"; # default browser setting popup
sleep 3;
sendkey "alt-f4";
sleep 1;
sendkey "ret"; # save+quit
sendkey "alt-f4"; # close xterm

sleep 3;
sendkey "ctrl-alt-delete"; # does open task manager instead of reboot
sleep 5;

sendkey "alt-f2";
waitidle;
sleep 2;
sendautotype "xterm\n";
waitidle;
script_sudo "/sbin/reboot";

sleep 10;
waitinststage "LXDE";
sleep 10;

qemusend "system_powerdown";

1;
