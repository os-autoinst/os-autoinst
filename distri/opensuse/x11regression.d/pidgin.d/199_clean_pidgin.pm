use base "basetest";
use bmwqemu;

# Cleaning for testing pidgin

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

        # Remove packages
        sendautotype("xdg-su -c 'rpm -e @packages'\n");
        waitidle;sleep 3;
        if ($password){
        	sendpassword;
                sendkeyw "ret";
        }
        waitidle; sleep 10;
        sendautotype("clear\n");
	sleep 2;
        sendautotype("rpm -qa @packages\n");
        waitidle;sleep 2;
        waitforneedle ("pidgin-pkg-removed",10); #make sure pkgs installed
        waitidle;sleep 2;
        sendkey "alt-f4";sleep 2; #close xterm

}

sub run()
{
	my $self=shift;
        install_pkg;
}

1;
