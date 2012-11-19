use base "basetest";
use bmwqemu;

sub is_applicable()
{
       return !defined($ENV{ADDONURL}) && $ENV{BIGTEST};
}

sub run()
{ my $self=shift;
	script_run("cd /tmp ; wget -q http://w3.suse.de/~bwiedemann/suseqa/qa_openstack.sh");
	#script_run("cd /tmp ; wget -q http://openqa.suse.de/sle/qatests/qa_openstack.sh");
	{
		local $ENV{SCREENSHOTINTERVAL}=2;
		script_sudo("sh -x qa_openstack.sh");
		waitstillimage(60, 900);
		sendkey "ctrl-c"; # stop watching du
		sleep 6; # allow the remainder of qa_openstack.sh to finish
		$self->take_screenshot; sleep 2;
	}
	sendkey "ctrl-l"; # clear screen
	sendautotype "echo ret=\$?\n"; sleep 2;
}

1;
