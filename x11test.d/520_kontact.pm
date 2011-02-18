use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} eq "kde";
}

sub run()
{
	my $self=shift;
	x11_start_program("kontact");
	sleep 10; waitidle 100; sleep 10; # pim needs extra time for first init
	$self->take_screenshot;
	sendkey "alt-f4"; sleep 10; # close popup (tips on startup)
	$self->take_screenshot;
	sendkey "alt-f4";

}

sub checklist()
{
	# return hashref:
	return {qw(
		0791f673be71d1ce43788135fc6aa0f7 OK
		5bf3bbb9c13f6297856702935f910735 OK
		37b3b3ab3db499d7a82e47164fe9264c OK
		553f19500f672d1b258300bb4a670e3b OK
		1518f09067c55dbcd5abec1a14ac7cb0 OK
		b911aaec3dde67b3d1c889c3b2f75089 OK
		6775249e0f12977a37f1fe431836d3ca OK
		550c0488d60c4cfedf67a88d88d857f2 OK
		d3126e3f02fdb4ba886e296d056160c5 OK
		acc6f4ab97b4b7c3ef170d1d8321eb04 OK
		43afb9514e7ed9e098a957e2ef5c34ab OK
	)}
}

1;
