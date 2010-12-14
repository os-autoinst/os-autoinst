#!/usr/bin/perl -w
use bmwqemu;
# workaround for bug
# usage: $0 | netcat localhost 16223
my $standalone=0;
if($standalone) {
	open(bmwqemu::LOG, ">/dev/null");
	open($bmwqemu::managementcon, ">&STDOUT");
	select $bmwqemu::managementcon;
	$|=1;
	select STDOUT;
}
sub script_runx($) {sendautotype($_[0]."\n");sleep 2}


sendautotype("n\n"); # decline alternate boot dev
sleep 2;
script_runx("mdadm --stop /dev/md0");
script_runx("mdadm --assemble /dev/md0 /dev/vda2 /dev/vdb2 /dev/vdc2 /dev/vdd2");
sendkey("ctrl-d"); # end initrd shell - continue booting
sleep 20; # time to boot more

