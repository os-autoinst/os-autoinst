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
		f1cdef309024d7629020da33248e63f5 OK
		aef1986f321c80ea98c62a7f1a0eb315 OK
		b53208e8481bfa42280184505826b06f OK
		d24465c763eccca55eca712dc5820a95 OK
		614838262da0d1976e84aba2e4636f01 fail
		0ca35889f8b2ff0eff07304f65fdeb79 fail
	)}
}

1;
