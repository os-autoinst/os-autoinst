use base "basetest";
use bmwqemu;
# test yast2 lan functionality
# https://bugzilla.novell.com/show_bug.cgi?id=600576


sub run()
{ my $self=shift;
script_sudo("/sbin/yast2 lan");

if($ENV{LIVETEST} || $ENV{DISTRI} eq "sled-11") {
	sendkey "ret";   # confirm networkmanager popup
	sleep 1;
	sendkey "alt-t"; # traditional ifup
	sleep 1;
}

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
$self->take_screenshot;
sendkey("alt-o"); # confirm possible network manager warning
sendkey("alt-o"); # OK=>Save&Exit
sleep 20;
waitidle();
waitidle(180);

sendkey("ret");
sendkey("ctrl-l"); # clear screen
script_run('echo $?');
script_run('hostname');
}

sub checklist()
{
	# return hashref:
	return {qw(
		5660b88237419b9c34efe4bfc6de960f OK
		9b1e290f49eac89a827d488114d9309c fail
		cbcdd79e992fb5a8be0c834616eeeb40 fail
	)}
}

1;
