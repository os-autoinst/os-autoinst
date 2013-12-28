use base "installstep";
use strict;
use bmwqemu;

sub run()
{
	waitidle(2000);
	waitstillimage(60,3600);
	mouse_hide();
	my $pic = 1;
	if (waitinststage('mageia4-setupusers-nopic',10)) {
	$pic = 0;
	$ENV{DESKTOP} = 'none';
	print "No user picture, as no desktop installed";
	} elsif (waitinststage('mageia4-setupusers-pic',10) || waitinststage('mageia4-setupusers-pic1',10)) {
	print "user picture is avilable";
	$pic = 2;
	} else {
	print "Sorry, can't recoginse user input stage";
	die ("no matching user input stage identified, please update md5sums");
	}
#	waitgoodimage(1200);
        sendautotype "$password\t"; # root PW
	sleep 1;
        sendautotype "$password"; # root PW
	sleep 1;

	if ($pic == '2') {
	print "Skipping past users picture";
        sendkey "tab"; # User icon
	sleep 1;
	} 
	
        sendkey "tab"; # skip media check
	sleep 1;
        sendautotype "$realname\t"; # Test user
	sleep 1;
        sendautotype "$username\t"; # Test user
	sleep 1;
        sendautotype "$password\t"; # root PW
	sleep 1;
        sendautotype "$password"; # root PW
	sleep 1;
        sendkey "tab"; # skip media check
	sleep 1;
        sendkey "tab"; # skip media check
	sleep 1;
	sendkey "tab"; # skip media check
	sleep 1;
	sendkey "ret";


}

1;
