use strict;
use base "installstep";
use bmwqemu;

sub is_applicable()
{
	my $self=shift;
	return $self->SUPER::is_applicable && !$ENV{LIVECD} && $ENV{UPGRADE};
}

sub run()
{
	my $self=shift;
	# upgrade system select
	sendkeyw "alt-c"; # "Cancel" on warning popup (11.1->11.3)
	sendkeyw "alt-s"; # "Show All Partitions"

	$self->take_screenshot;
	sendkeyw $cmd{"next"};
	# repos
	$self->take_screenshot;
	sendkeyw $cmd{"next"};
	# might need to resolve conflicts here
	if($ENV{UPGRADE}=~m/11\.1/) {
		sendkeyw "alt-c";
		sendkeyw "p";
	# alt-c p # Change Packages
		for(1..4) {sendkey "tab"}
		sendkey "spc";
		sleep 3;
		sendkeyw "alt-o";
	# tab tab tab tab space alt-o # Select+OK
		sendkeyw "alt-a";
		sendkey "alt-o";
	# alt-a alt-o # Accept + Continue(with auto-changes)
	}
	# hack: button on summary screen is labeled Upgrade instead of Install
	$cmd{install}="alt-u"; 
	$cmd{software}="p"; # select "Packages" in change_software step
	if($ENV{VIDEOMODE} ne "text") {
		$ENV{DOCRUN}=1; # to show conflicts
	}
}

1;
