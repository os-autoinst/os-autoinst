use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	waitidle;
	sendkey "ret"; # inetd
	sendkey "ret"; # SSH
	sendkey "ret"; # FTP
	sendkey "ret"; # NFS-server
	sendkey "ret"; # NFS-client
	sendkey "ret"; # console-settings
}

1;
