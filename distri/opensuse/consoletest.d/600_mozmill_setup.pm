use base "basetest";
use bmwqemu;
# http://mozmill-crowd.blargon7.com/#/functional/reports

sub is_applicable()
{
	return ($ENV{MOZILLATEST});
}

sub run()
{
	my $self=shift;
	script_sudo("zypper -n in gcc python-devel python-pip mercurial curlftpfs");
	$self->check_screen;
	sendkey "ctrl-l";
	#script_sudo("pip install mozmill mercurial");
	script_sudo("pip install mozmill mercurial");
	#script_sudo("pip install mozmill==1.5.3 mercurial");
	sleep 5; waitidle(50);
	$self->check_screen;
	sendkey "ctrl-l";
	script_run("cd /tmp"); # dont use home to not confuse dolphin test
	script_run("wget -q openqa.opensuse.org/opensuse/qatests/qa_mozmill_setup.sh");
	local $bmwqemu::timesidleneeded=3;
	script_run("sh -x qa_mozmill_setup.sh");
	sleep 9;
	waitidle(90);
	waitserial("qa_mozmill_setup.sh done", 120) || die 'setup failed';
	$self->take_screenshot;
}

1;
