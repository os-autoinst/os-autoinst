use base "basetest";
use bmwqemu;

# test for https://bugzilla.novell.com/show_bug.cgi?id=730103

sub is_applicable()
{
       return !defined($ENV{RAIDLEVEL})
}

sub run()
{ my $self=shift;
	script_run("cd /tmp ; wget -q openqa.opensuse.org/opensuse/qatests/qa_btrfs.sh");
	{
		local $ENV{SCREENSHOTINTERVAL}=2;
		script_sudo("sh -x qa_btrfs.sh");
		waitserial("xfstests done", 3900);
		$self->take_screenshot; sleep 2;
	}
	sendkey "ctrl-l"; # clear screen
	sendautotype "echo ret=\$? survived btrfstest\n"; sleep 2;
}

1;
