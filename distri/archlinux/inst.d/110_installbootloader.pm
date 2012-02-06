use base "basenoupdate";
use strict;
use bmwqemu;

sub run()
{
	my $self=shift;
	sendkey "8"; # bootloader
	sendkeyw "ret"; # ok

	sendkey "ret"; # close info box
	sleep 1;
	sendautotype ":q\n";
	sleep 1;
	sendkey "end"; # select sda
	sleep 1;
	sendkey "ret"; # select device
	sleep 8;
	$self->take_screenshot;
	if(waitimage('installbootloader-1', 10)) {
		sendkey "ret"; # close 1st error message
	}
	sleep 1;
	sendkey "ret"; # close info box
}

1;
