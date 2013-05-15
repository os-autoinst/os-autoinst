use base "basetest";
use bmwqemu;
# test for equivalent of bug https://bugzilla.novell.com/show_bug.cgi?id=
sub run()
{
	my $self=shift;
	script_run('test -L /etc/mtab && echo OK || echo fail');
	$self->check_screen;
	script_run('cat /etc/mtab');
}

1;
