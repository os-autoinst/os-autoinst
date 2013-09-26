use base "basetest";
use bmwqemu;

# Case 1248849 - Pidgin: IRC

my $IRC=7;
my $CHANNELNAME="susetesting";

sub is_applicable()
{
	return $ENV{DESKTOP}=~/kde|gnome/;
}

sub run()
{
	my $self=shift;
	x11_start_program("pidgin");
	waitidle; sleep 2;
        # Create account
        sendkey "alt-a";
        sleep 2;
        sendkey "spc";
        sleep 2;
	# Choose Protocol "IRC"
        foreach(1..$IRC){
		sendkey "down";
                sleep 1;
        }
        sendkey "ret"; sleep 2;
        sendkey "alt-u"; sleep 1;
        sendautotype("$CHANNELNAME");sleep 2;
	sendkey "alt-a"; 
        waitidle; sleep 10;
	# Should create IRC account
	$self->check_screen;

	# Close account manager
	sendkey "ctrl-a"; sleep 2;
	sendkey "alt-c"; sleep 2;
	# Join a chat
	sendkey "ctrl-c"; sleep 2;
        # input "#"
	sendkey "shift-3"; sleep 2;
        sendautotype("sledtesting");sleep 2;
	sendkey "alt-j";  
        waitidle; sleep 10;
	# Should open sledtesting channel
	$self->check_screen;

        # Cleaning
	sendkey "ctrl-a"; sleep 2;
	sendkey "right"; sleep 2;
	sendkey "ret"; sleep 2;
	sendkey "alt-d"; sleep 2;
	sendkey "alt-d";
        waitidle; sleep 2;
	# Should not have any account
	$self->check_screen;
	
        # Exit
	sendkey "alt-c"; sleep 2;
	sendkey "ctrl-q"; sleep 2;
}


1;
