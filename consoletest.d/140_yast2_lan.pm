use base "basetest";
use bmwqemu;
# test yast2 lan functionality
# https://bugzilla.novell.com/show_bug.cgi?id=600576


sub run()
{ my $self=shift;
script_sudo("/sbin/yast2 lan");
waitstillimage();

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
		643fbda2f009ecef30f0b6d331124380 OK
		4db03d05d1f653a50e3c0eb2b20bd69a OK
		2562e77bdce25069258bdb8748c3c302 OK
		66e4a815edf5460d9975e04a1db70b39 OK
		b713aaca3ea534257c4ed81529d04c62 OK
		7300bd5354c5a6fa1afbe898acbf9fe0 OK
		645d750e368d3d843b51e33ccbcc0922 OK
		5660b88237419b9c34efe4bfc6de960f OK
		2211a4356673d79819671bb9ae36cba0 OK
		9b1e290f49eac89a827d488114d9309c fail
		cbcdd79e992fb5a8be0c834616eeeb40 fail
	)}
}

1;
