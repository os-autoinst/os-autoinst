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

sub checklist()
{
	# return hashref:
	return {qw(
		a5fbe661f892c38c5069bf3430cac25b OK
		190acc3807f1f613aae461f805473e02 OK
		b4d6d76baae4254e0e01140bed1614e3 OK
		cab8e1d51a429d42ad922c88a786d591 OK
		bd32d2896fe9ee327724bce46ffe32be OK
		6edae3afba71dd93f7615791af5e4912 OK
		6491e203e83083d77b603853dde03f5c OK
		6e2f20a265525ef64a777ade0d29bc95 OK
		baf11490d0809edc8c9abea408f53eb7 OK
		26023f0d3a37046730c47ee40115fd74 OK
		1aa2225b803c4712e2213d8639131b2c minorissue64bit
	)}
}


sub ocr_checklist()
{
        [

                {screenshot=>2, x=>104, y=>201, xs=>380, ys=>150, pattern=>"H ?ello", result=>"OK"}
        ]
}


1;
