use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{DESKTOP} =~ m/gnome|kde|xfce|lxde/;
}

sub run()
{
	my $self=shift;
	if($ENV{DESKTOP} eq "lxde") {
		x11_start_program("lxpanelctl menu"); # or Super_L or Windows key
	} elsif($ENV{DESKTOP} eq "xfce") {
		mouse_set(0,0);
		sleep 1;
		sendkey "ctrl-esc";	# open menu
		sleep 1;
		sendkey "up";		# go into Applications submenu
	} else {
		sendkey "alt-f1"; # open main menu
	}
	sleep 2;
	sleep 10 if $ENV{NICEVIDEO};
	$self->check_screen;
	sendkey "esc"; 
	waitidle;
}

sub ocr_checklist()
{
        [

                {screenshot=>1, x=>30, y=>30, xs=>200, ys=>250, pattern=>"(?si:ccessories.*Internet.*ffice.*Universal .ccess)", result=>"OK"}, # gnome
                {screenshot=>1, x=>20, y=>5, xs=>200, ys=>250, pattern=>"(?si:reate .auncher.*reate..?older.*pen Terminal Here.*rrange Des.top .cons)", result=>"OK"}, # xfce
                {screenshot=>1, x=>56, y=>510, xs=>200, ys=>300, pattern=>"(?si:Pers.nal.*Help.*Terminal)", result=>"OK"}, # kde 1280x960
#                {screenshot=>1, x=>20, y=>500, xs=>200, ys=>250, pattern=>"(?si:Accessories.*System.*Logout)", result=>"OK"} # lxde - already matched with img
        ]
}



1;
