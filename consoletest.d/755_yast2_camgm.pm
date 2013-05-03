use base "basetest";
use bmwqemu;

sub is_applicable()
{ 0 }

sub run()
{
	my $self=shift;
	script_sudo("/sbin/yast2 ca_mgm");
	waitstillimage(12,90);
	sendkeyw "alt-c"; # create root CA
	sendautotype "autoinstCA\tsusetest.zq1.de\t\t\t\tOrg\tOU\topenQAserver\tfranconia\t\b\b\bGermany";
	sendkeyw "alt-n";
	sendautotype "$password\t$password";
	sendkeyw "alt-n";
	sendkeyw "alt-t"; # create CA
	
	if(1) {
		sendkey "alt-e"; # enter CA
		sendautotype $password;
		sendkey "alt-o"; # OK
		sendkey "alt-e"; # cErtificates
		sendkey "alt-a"; # add
		sendkeyw "ret";   # Server cert
		sendautotype "susetest.zq1.de";
		sendkeyw "alt-n";
		sendkey "alt-u"; # Use CA pw
		sendkeyw "alt-n";
		sendkeyw "alt-t"; # creaTe cert

		sendkey "alt-x"; # eXport
		sendkey "down";
		sendkey "down";
		sendkeyw "ret"; # Export as Common Server Certificate
		$self->check_screen(); sleep 1;
		sendkey "alt-o"; # hostname warning - might or might not be needed
		sendkeyw "alt-p"; # select PW field
		sendautotype $password;
                sendkeyw "alt-o"; # OK
                sendkey "alt-o"; # OK "has been written"
		# files are in /etc/ssl/servercerts/server*

		sendkey "alt-o"; # OK

	}

	sendkeyw "alt-f"; # finish
	script_run('echo $?');
	script_run('wget http://openqa.opensuse.org/opensuse/qatests/imapcert.sh');
	script_sudo('bash -x imapcert.sh');
}

1;
