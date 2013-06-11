use base "basetest";
use bmwqemu;
# test for equivalent of bug https://bugzilla.novell.com/show_bug.cgi?id=598574
sub is_applicable()
{
	return ($ENV{BIGTEST});
}

sub run()
{
	my $self=shift;
	script_run('rpm -q wget');
	script_run('wget -O- -q www3.zq1.de/test.txt');
	$self->check_screen;
}

1;
