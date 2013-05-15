use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} eq "gnome" && !$ENV{LIVECD};
}

sub run()
{
	my $self=shift;
	x11_start_program("banshee");
	$self->check_screen;
	sendkey "ctrl-q"; # really quit (alt-f4 just backgrounds)
	sendkey "alt-f4"; 
	waitidle;
}

sub ocr_checklist()
{
        [

                {screenshot=>1, x=>8, y=>150, xs=>140, ys=>380, pattern=>"(?si:Vide.s.*Fav.rites.*Unwatched)", result=>"OK"}
        ]
}

1;
