use base "basenoupdate";
use strict;
use bmwqemu;

sub run()
{ my $self=shift;
	waitstillimage(20,60);
	mouse_hide;
	$self->take_screenshot;
        sendkeyw "alt-n";
	if($ENV{ADDONURL}=~m/-HA-LATEST\/x86_64/) {
		# workaround xen on HA x86_64 oddity
		$self->take_screenshot;
		sendkeyw "alt-i"; # confirm install bridge-utils on HA
	}
	sleep 10;
	waitstillimage(20,60);
}

1;
