use base "basetest";
use bmwqemu;

# Case 1248850 - Pidgin: Google talk

my $GOOGLETALK=4;
my $USERNAME="nooops6";
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
        sendkey "alt-a";
        sleep 2;
        sendkey "spc";
        sleep 2;
        # Choose Protocol "GOOGLETALK"
        foreach(1..$GOOGLETALK){
                sendkey "down";
                sleep 1;
        }
        sendkey "ret"; sleep 2;
        sendkey "alt-u"; sleep 1;
        sendautotype("$USERNAME");sleep 2;
        sendkey "alt-p"; sleep 1;
        sendautotype("$PASSWD");sleep 2;
        sendkey "alt-a";
        waitidle; sleep 15;
        # Should create GoogleTalk account
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
        # Should not have any account
        $self->check_screen;

        # Exit
        sendkey "alt-c"; sleep 2;
        sendkey "ctrl-q"; sleep 2;
}


1;
