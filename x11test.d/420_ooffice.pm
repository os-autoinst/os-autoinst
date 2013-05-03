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
	$self->check_screen;
	sendautotype("Hello World!");
	sleep 2;
	$self->check_screen;
	sendkey "alt-f4"; sleep 2;
	$self->check_screen;
	sendkey "alt-d"; sleep 2; # Discard
}

sub ocr_checklist()
{
        [

                {screenshot=>2, x=>104, y=>201, xs=>380, ys=>150, pattern=>"H ?ello", result=>"OK"}
        ]
}


1;
