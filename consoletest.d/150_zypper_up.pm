use bmwqemu;
script_sudo("zypper -n -q up");
waitidle;

1;
