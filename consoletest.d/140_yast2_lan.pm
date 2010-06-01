use bmwqemu;
# test yast2 lan functionality
# https://bugzilla.novell.com/show_bug.cgi?id=600576

script_sudo("/sbin/yast2 lan");

my $hostname="susetest";
my $domain="zq1.de";

sendkey("alt-s"); # open hostname tab
sleep 2;
sendkey("tab");
for(1..15){sendkey("backspace")}
sendautotype($hostname);
sendkey("tab");
for(1..15){sendkey("backspace")}
sendautotype($domain);
sleep 3;
sendkey("alt-o"); # OK=>Save&Exit
waitidle(180);
sleep 10;

sendkey("ctrl-l"); # clear screen
script_run('echo $?');
#script_run("exec su - $username"); # get new hostname on prompt
#sendautotype("$password\n");
#sleep 3;
script_run('hostname');

1;
