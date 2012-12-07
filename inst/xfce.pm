use bmwqemu;

mouse_hide(1);
waitidle;
sendkey "tab";
sendkey "ret";
sleep 5;
do "inst/consoletest.pm";

1;
