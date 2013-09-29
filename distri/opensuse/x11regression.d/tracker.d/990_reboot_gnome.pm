use base "basetest";
use bmwqemu;

sub is_applicable()
{
        return (($ENV{DESKTOP} eq "gnome") and (!$ENV{LIVETEST} or $ENV{USBBOOT}));
}

sub run()
{
        my $self=shift;
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
#                $self->check_screen;
                sendkey "ctrl-alt-delete"; # reboot
        }
}

1;
