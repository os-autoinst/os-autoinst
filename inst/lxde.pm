use bmwqemu;

waitinststage "LXDE";
mousemove_raw(31000, 31000); # move mouse off screen again
waitidle;
sleep 5;
x11_start_program("killall xscreensaver");
do "inst/consoletest.pm";

1;
