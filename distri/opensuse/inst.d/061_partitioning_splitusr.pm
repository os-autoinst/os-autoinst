use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return $ENV{SPLITUSR};
}

sub run()
{
	my $self=shift;
	sendkeyw "alt-e";  # Edit
	# select vda2
	sendkey "right"; sendkey "down"; # only works with multiple HDDs
	sendkey "right"; sendkey "down";
	sendkey "tab"; sendkey "tab"; sendkey "down";
	#sendkey "right"; sendkey "down"; sendkey "down";
	sendkeyw "alt-i"; # Resize
	sendkey "alt-u"; # Custom
	sendautotype "1.5G";
	sleep 2;
	sendkeyw "ret";
	# add /usr
	sendkey $cmd{addpart};
	waitidle 4;
	sendkey $cmd{"next"};
	waitidle 3;
	for(1..10) {
		sendkey "backspace";
	}
	sendautotype("4.5G");
	sendkeyw $cmd{"next"};
	sendkey "alt-m"; # Mount Point
	sendautotype("/usr\b"); # Backspace to break bad completion to /usr/local
	sendkey $cmd{"finish"};
	sendkeyw $cmd{"accept"};
}

sub checklist()
{
	# return hashref:
	return {qw(
	)}
}

1;
