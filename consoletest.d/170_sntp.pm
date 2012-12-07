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
	$self->take_screenshot;
	sendkey("ctrl-l"); # clear screen
	script_run('echo sntp returned $?');
}

sub checklist()
{
	# return hashref:
	return {qw(
		8049fb04102e6ddb8ff7917711952356 OK
		5680ef72fff30f8dc97112933b61d248 OK
		76b6474caffab43b674e109512c313b0 OK
		0f9ebcbf2e296cb70ed7649d4c5d3b07 fail
	)}
}

1;
