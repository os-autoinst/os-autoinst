use base "basetest";
use bmwqemu;

# Case 1248853 - Pidgin: Add MSN Account
# Case 1248854 - Pidgin: Login to MSN and Send/Receive message

my $MSN=8;
my $USERNAME="nooops_test2";
my $DOMAIN="hotmail";
my $PASSWD="OPENsuse";

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
	# Choose Protocol "MSN"
        sendkey "spc";
        sleep 2;
        foreach(1..$MSN){
		sendkey "down";
                sleep 1;
        }
        sendkey "ret"; sleep 2;
        sendkey "alt-u"; sleep 1;
        sendautotype("$USERNAME");sleep 2;
        sendkey "shift-2";sleep 2;
        sendautotype("$DOMAIN");sleep 2;
        sendkey "dot"; sleep 1;
        sendautotype("com");sleep 2;
        sendkey "alt-p"; sleep 1;
        sendautotype("$PASSWD");sleep 2;
	sendkey "alt-a"; 
        waitidle; sleep 45; # Connect to MSN are very slow
	# Should create MSN account
	$self->check_screen;

	# Close account manager
	sendkey "ctrl-a"; sleep 2;
	sendkey "alt-c"; sleep 2;
	# Open a chat
	sendkey "tab"; sleep 2;
	sendkey "down"; sleep 2;
	sendkey "ret"; sleep 2;
        sendautotype("hello world!\n");sleep 2;
        waitidle; sleep 10;
	# Should see "hello world!" in screen.
	$self->check_screen;

        # Cleaning
        # Close the conversation
	sendkey "ctrl-w"; sleep 2;
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
