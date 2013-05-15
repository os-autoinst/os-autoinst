use base "basetest";
use bmwqemu;
# for https://bugzilla.novell.com/show_bug.cgi?id=657626

sub is_applicable()
{
	return ($ENV{MOZILLATEST});
}

sub run()
{
	my $self=shift;
	x11_start_program("xterm");
	script_run("cd /tmp");
	script_run("wget -q openqa.opensuse.org/opensuse/qatests/qa_mozmill_run.sh");
	local $ENV{SCREENSHOTINTERVAL}=0.25;
	script_run("sh -x qa_mozmill_run.sh");
	sleep 30;
	local $bmwqemu::timesidleneeded=4;
	for(1..12) { # one test takes ~7 mins
		sendkey "shift"; # avoid blank/screensaver
		last if waitserial("mozmill testrun finished", 120);
	}
	$self->check_screen;
	sendkey "alt-f4";
}

1;
