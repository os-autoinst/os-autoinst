use base "basetest";
use bmwqemu;
# for https://bugzilla.novell.com/show_bug.cgi?id=679459

sub is_applicable()
{
	return ($ENV{BIGTEST});
}

sub run()
{
	my $self=shift;
	script_run("cd /tmp ; wget -q openqa.opensuse.org/opensuse/qatests/qa_syslinux.sh");
	sendkey "ctrl-l";
	script_sudo("sh -x qa_syslinux.sh");
	$self->check_screen;
}

1;
