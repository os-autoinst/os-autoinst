use bmwqemu;

waitinststage "LXDE";
waitidle;
sleep 5;
x11_start_program("killall xscreensaver");
do "inst/consoletest.pm";

1;
