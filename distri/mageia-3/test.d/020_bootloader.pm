use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	# boot
	sendkey "down";
	waitstillimage(10,20);
	$self->take_screenshot;
	sleep 5;
	power('off');	
}

sub checklist()
{
        # return hashref:
        return {qw(
5c39a790a48eccf0b91f6bffa13e9b12 OK
        )}
}


1;
