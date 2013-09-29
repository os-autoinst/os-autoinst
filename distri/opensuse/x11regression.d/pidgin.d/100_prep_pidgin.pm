use base "basetest";
use bmwqemu;

# Preparation for testing pidgin

my @packages=qw/pidgin pidgin-otr/;

sub is_applicable()
{
        return $ENV{DESKTOP}=~/kde|gnome/;
}

sub install_pkg()
{
        my $self=shift;

        x11_start_program("xterm");
        sendautotype("rpm -qa @packages\n");
        waitidle;sleep 5;

        # Remove screensaver
        sendautotype("xdg-su -c 'rpm -e gnome-screensaver'\n");
        waitidle;sleep 3;
        if ($password){
                sendpassword;
                sendkeyw "ret";
        }

        # Install packages
        sendautotype("xdg-su -c 'zypper -n in @packages'\n");
        waitidle;sleep 3;
        if ($password){
                sendpassword;
                sendkeyw "ret";
        }
        sleep 60;
        sendautotype("\n");       # prevent the screensaver...
        waitforneedle ("pidgin-pkg",500); #make sure pkgs installed
        waitidle;sleep 2;
        sendautotype("rpm -qa @packages\n");
        waitidle;sleep 2;
        waitforneedle ("pidgin-pkg-installed",10); #make sure pkgs installed
        waitidle;sleep 2;
        sendkey "alt-f4";sleep 2; #close xterm

        # Enable the showoffline
        x11_start_program("pidgin");
        waitidle; sleep 2;

        sendkey "alt-c"; sleep 2;
        x11_start_program("pidgin");
        sendkey "alt-b"; sleep 2;
        sendkey "o";
        waitidle;sleep 2;
        waitforneedle ("pidgin-showoff",10); #enable show offline
        sendkey "o"; 

        sendkey "ctrl-q"; sleep 2;
}

sub run()
{
        my $self=shift;
        install_pkg;
}

1;
