use bmwqemu;

mouse_hide(1);
waitidle;
sleep 5;
x11_start_program("killall xscreensaver");
do "inst/consoletest.pm";

1;
