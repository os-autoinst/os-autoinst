use base "basetest";
use bmwqemu;

# Case 1248855 - Pidgin: Add AIM Account
# Case 1248856 - Pidgin: Login to AIM Account and Send/Receive Message

my $AIM=0;
my $USERNAME="nooops_test3";
my $USERNAME1="nooops_test4";
my $DOMAIN="aim";
my $PASSWD="opensuse";

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
        sendkey "alt-a"; sleep 2;
	# Choose Protocol "AIM",which is by default
        #sendkey "spc";
        #sleep 2;
        #foreach(1..$AIM){
	#	sendkey "down";
        #        sleep 1;
        #}
        #sendkey "ret"; sleep 2;
        sendkey "alt-u"; sleep 1;
        sendautotype("$USERNAME");sleep 2;
        sendkey "shift-2";sleep 2;
        sendautotype("$DOMAIN");sleep 2;
        sendkey "dot"; sleep 1;
        sendautotype("com");sleep 2;
        sendkey "alt-p"; sleep 1;
        sendautotype("$PASSWD");sleep 2;
	sendkey "alt-a"; 
        waitidle; sleep 15;
	# Should create AIM account 1
	$self->check_screen;

        # Create another account
        sendkey "ctrl-a"; sleep 2;
        sendkey "alt-a"; sleep 2;
        sendkey "alt-u"; sleep 1;
        sendautotype("$USERNAME1");sleep 2;
        sendkey "shift-2";sleep 2;
        sendautotype("$DOMAIN");sleep 2;
        sendkey "dot"; sleep 1;
        sendautotype("com");sleep 2;
        sendkey "alt-p"; sleep 1;
        sendautotype("$PASSWD");sleep 2;
	sendkey "alt-a"; 
        waitidle; sleep 15;
	# Should have AIM accounts 1 and 2
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
        # Remove one account
	sendkey "ctrl-a"; sleep 2;
	sendkey "right"; sleep 2;
	sendkey "ret"; sleep 2;
	sendkey "alt-d"; sleep 2;
	sendkey "alt-d";
        waitidle; sleep 2;
        # Remove the other account
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
