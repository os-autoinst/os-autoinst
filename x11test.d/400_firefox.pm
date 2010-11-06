use base "basetest";
use bmwqemu;

sub run()
{
	my $self=shift;
	x11_start_program("firefox");
	$self->take_screenshot;
	if($ENV{DESKTOP}=~/xfce|lxde/i) {
		sendkey "ret"; # confirm default browser setting popup
		waitidle;
	}
	$self->take_screenshot;
	sendkey "alt-f4"; sleep 2;
	sendkey "ret"; # confirm "save&quit"
}

sub checklist()
{
	# return hashref:
	# firefox disabled icons (back, forw, stop) differ by one bit between 32/64 arch
	return {qw(
		fc382651f1e1b6359789038ad0bd9bc0 OK
		4299006210d21ee52570d99916500f76 OK
		a10028c503d80f78603f4bd79cbab29d OK
		c787a8ef735af6b96f91c632fe204228 OK
		0be87757a2521271a1ac41e70fbdea92 OK
		19daee9720e63ad62491dc7d70857f1e OK
		5744e0f67ade6afdac118940b61d1312 OK
	)}
}

1;
