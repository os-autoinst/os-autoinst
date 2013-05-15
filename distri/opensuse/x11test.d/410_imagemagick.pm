use base "basetest";
use bmwqemu;
# for https://bugzilla.novell.com/show_bug.cgi?id=717871

sub is_applicable()
{
	return ($ENV{BIGTEST});
}

sub run()
{
	my $self=shift;
	x11_start_program("xterm");
	script_run("cd /tmp; mkdir img ; cd img");
	script_run("curl openqa.opensuse.org/opensuse/qatests/img.tar.gz | tar xz");
	script_run("ls;display *.png");
	for(1..3){
		sendkey "spc"; sleep 3;
		$self->check_screen;
	}
	sendkey "alt-f4"; # close display
	sendkey "alt-f4"; # close xterm
}

1;
