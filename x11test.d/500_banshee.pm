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
	$self->take_screenshot;
	sendkey "ctrl-q"; # really quit (alt-f4 just backgrounds)
	sendkey "alt-f4"; 
	waitidle;
}

sub checklist()
{
	# return hashref:
	return {qw(
		055ef0f7abcff0ebf91f545ce290ef9a OK
		9b0ed4c97220f047a16252aad1aca253 OK
		b178bcd5587d55b8fc5aadfd1e18bad0 OK
	)}
}

sub ocr_checklist()
{
        [

                {screenshot=>1, x=>8, y=>150, xs=>140, ys=>380, pattern=>"(?si:ying.*Vide.s.*Fav.rites.*Unwatched)", result=>"OK"}
        ]
}

1;
