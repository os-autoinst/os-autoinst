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
	if( $ENV{DESKTOP} eq "kde" || $ENV{DESKTOP} eq "gnome" ) {
            waitidle;
            sendkey "ctrl-alt-delete"; # reboot
            waitforneedle 'logoutdialog', 15;
            sendautotype "\t\t";
            sleep 1;
            sendautotype "\n";
        }

        # 550_reboot_xfce
	if( $ENV{DESKTOP} eq "xfce" ) {
            sendkey "ctrl-alt-delete"; # reboot
            waitforneedle 'logoutdialog', 15;
            #waitidle;
            #sendkey "alt-f4"; # open popup
            #waitidle;
            sendkey "tab"; # reboot
            sleep 1;
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

        # 570_xfce_login_after_reboot
	if( $ENV{NOAUTOLOGIN} || $ENV{XDMUSED} ) {
            waitforneedle('displaymanager', 200);
            waitidle;

            # log in
            sendautotype $username."\n";
            sleep 1;
            sendautotype $password."\n";
        }

        waitforneedle 'test-consoletest_finish-1', 300;
	mouse_hide(1);
}

sub test_flags() {
        return {'milestone' => 1, 'fatal' => 1};
}
1;

