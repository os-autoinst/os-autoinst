use base "basetest";
use bmwqemu;

sub run()
{
	my $self=shift;

	# wait until ready
	mouse_hide(1);
	waitidle 100;


	if (checkEnv('DESKTOP', 'gnome')) {
		sleep 10;

		if(!$ENV{NICEVIDEO}) {
			x11_start_program("killall gnome-screensaver");
		}

	}
	if (checkEnv('DESKTOP', 'kde')) {
		sleep 10;

		my %kdemenu=(firefox=>1, pim=>2, office=>3, audio=>4, fileman=>5, config=>6, help=>7, xterm=>8);
		if($ENV{NETBOOT}) { # has photomanager added on #5
			#       $kdemenu{audio}++; # and office on #3
			for my $x (qw(fileman config help xterm)) {
				$kdemenu{$x}+=1;
			}
		}
	}

	if (checkEnv('DESKTOP', 'xfce')) {
		sendkey "tab";
		sendkey "ret";
		sleep 5;
	}

	if (checkEnv('DESKTOP', 'lxde')) {
		sleep 5;
		x11_start_program("killall xscreensaver");
	}

}

1;
