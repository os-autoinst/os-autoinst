use base "basetest";
use bmwqemu;

sub is_applicable()
{
	return !$ENV{LIVETEST} || $ENV{USBBOOT};
}

sub run()
{
	my $self=shift;

        # 550_reboot_kde
	if( $ENV{DESKTOP} eq "kde" ) {
            waitidle;
            sendkey "ctrl-alt-delete"; # reboot
            waitidle(15);
            sendautotype "\t\t";
            sleep 1;
            $self->check_screen;
            sendautotype "\n";
        }

        # 550_reboot_gnome
	if( $ENV{DESKTOP} eq "gnome" ) {
            waitidle;
            if($ENV{GNOME2}) {
		sendkey "ctrl-alt-delete"; # reboot
		sleep 2;
		sendkey "down"; # reboot
		sleep 2;
		sendkey "ret"; # confirm 
		sleep 2;
		sendpassword;
		sendkey "ret";
            } else {
		sendkey "ctrl-alt-f4"; sleep 2; # goto console so that gnome does not catch CAD
		sendkey "ctrl-alt-delete"; # reboot
            }
        }
        
        # 550_reboot_xfce
	if( $ENV{DESKTOP} eq "xfce" ) {
            waitidle;
            sendkey "alt-f4"; # open popup
            waitidle;
            sendkey "tab"; # reboot
            waitidle;
            sendkey "ret"; # confirm 
        }

        # 550_reboot_lxde
	if( $ENV{DESKTOP} eq "lxde" ) {
            waitidle;
            #sendkey "ctrl-alt-delete"; # does open task manager instead of reboot
            x11_start_program("xterm");
            script_sudo "/sbin/reboot",0;
        }

	waitforneedle( "bootloader", 100); # wait until reboot
	if ($ENV{ENCRYPT}) {
	  wait_encrypt_prompt;
	}

	waitinststage "reboot-after-installation", 150; # wait until booted again
	mouse_hide(1);

        # 580_kde_reboot_plasmatheme
	if( $ENV{DESKTOP} eq "kde" ) {
            waitinststage "KDE", 20; # wait until reboot is finished
        }

        # 570_xfce_login_after_reboot
	if( $ENV{NOAUTOLOGIN} || $ENV{XDMUSED} ) {
            my $ok=waitinststage "dm-loginscreen", 80;
            if($ok) {
		waitidle;

		# log in
		sendautotype $username."\n";
		sleep 1;
		sendautotype $password."\n";
		waitinststage "XFCE", 40;
		sleep 5;
            }
        }
}

sub test_flags() {
        return {'milestone' => 1, 'fatal' => 1};
}
1;

