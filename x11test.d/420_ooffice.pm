use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP}=~/kde|gnome/;
}

sub run()
{
	my $self=shift;
	x11_start_program("oowriter");
	sleep 2; waitidle; # extra wait because oo sometimes appears to be idle during start
	$self->take_screenshot;
	sendautotype("Hello World!");
	sleep 2;
	$self->take_screenshot;
	sendkey "alt-f4"; sleep 2;
	$self->take_screenshot;
	sendkey "alt-w"; # Close _without saving
	sendkey "alt-d"; sleep 2; # Discard
}

sub ocr_checklist()
{
        [

                {screenshot=>2, x=>104, y=>201, xs=>380, ys=>150, pattern=>"H ?ello", result=>"OK"}
        ]
}


1;
