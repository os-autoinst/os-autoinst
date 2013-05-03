use base "basetest";
use bmwqemu;
# for https://bugzilla.novell.com/show_bug.cgi?id=657626

sub is_applicable()
{
	return ($ENV{BIGTEST});
}

sub run()
{
	my $self=shift;
	script_run("cd /tmp ; wget -q openqa.opensuse.org/opensuse/qatests/qa_ntp.pl");
	script_sudo("perl qa_ntp.pl");
	waitidle(90);
	$self->check_screen;
	sendkey("ctrl-l"); # clear screen
	script_run('echo sntp returned $?');
}

1;
