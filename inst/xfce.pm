use bmwqemu;

mousemove_raw(31000, 31000); # move mouse off screen again
waitidle;
sleep 5;
do "inst/consoletest.pm";

1;
