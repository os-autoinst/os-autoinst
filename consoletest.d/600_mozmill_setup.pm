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
	script_sudo("zypper -n in gcc python-devel python-pip mercurial curlftpfs");
	$self->take_screenshot;
	sendkey "ctrl-l";
	#script_sudo("pip install mozmill mercurial");
	script_sudo("pip install mozmill==1.5.1 mercurial");
	sleep 5; waitidle(50);
	$self->take_screenshot;
	sendkey "ctrl-l";
	script_run("cd /tmp"); # dont use home to not confuse dolphin test
	script_run("wget -q openqa.opensuse.org/opensuse/qatests/qa_mozmill_setup.sh");
	local $bmwqemu::timesidleneeded=3;
	script_run("sh -x qa_mozmill_setup.sh");
	sleep 5;
	waitidle(90);
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
