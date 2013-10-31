use base "basetest";
use bmwqemu;

sub is_applicable()
{
    return 1;
}

sub run()
{
	my $self=shift;

	if( $ENV{DESKTOP} eq "kde" ) {
            sendkey "ctrl-alt-delete"; # shutdown
            waitforneedle 'logoutdialog', 15;

            sendautotype "\t";
            waitforneedle("kde-turn-off-selected", 2);
            sendautotype "\n";
            waitinststage("splashscreen", 40);
        }

	if( $ENV{DESKTOP} eq "gnome" ) {
            sendkey "ctrl-alt-delete"; # shutdown
            waitforneedle 'logoutdialog', 15;

            sendkey "ret"; # confirm shutdown
            #if(!$ENV{GNOME2}) {
	    #    sleep 3;
	    #    sendkey "ctrl-alt-f1";
	    #    sleep 3;
	    #    qemusend "system_powerdown"; # shutdown
            #}
            waitinststage("splashscreen", 40);
        }

	if( $ENV{DESKTOP} eq "xfce" ) {
            for(1..5) {
		sendkey "alt-f4"; # opens log out popup after all windows closed
            }
            waitidle;
            sendautotype "\t\t"; # select shutdown
            sleep 1;
            #$self->check_screen;
            sendautotype "\n";
            waitinststage("splashscreen");
        }

	if( $ENV{DESKTOP} =~ m/lxde|minimalx|textmode/ ) {
            qemusend "system_powerdown"; # shutdown
            waitidle;
            #$self->check_screen;
            #sendkey "ctrl-alt-f1"; # work-around for LXDE bug 619769 ; not needed in Factory anymore
            waitinststage("splashscreen");
        }
}

1;
