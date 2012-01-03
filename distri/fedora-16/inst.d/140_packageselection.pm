use base "basetest";
use strict;
use bmwqemu;

sub run()
{
	# default = Graphical Desktop
	waitstillimage;
	if($ENV{HTTPPROXY} && $ENV{MIRROR}) {
		sendkey "tab";
		sendkey "tab"; # select main repo
		for my $n (1..2) {
			sendkey "alt-m"; sleep 2; # modify repo
			sendkey "alt-m"; # uncheck mirror list
			sendkey "alt-u"; # select URL
			if($n==1) {
				sendautotype $ENV{MIRROR}; # example: http://mirror.fraunhofer.de/download.fedora.redhat.com/fedora/linux/releases/16/Fedora/i386/os/
			} else {
				my $u=$ENV{MIRROR};
				$u=~s{/releases/(\d+)/Fedora/([0-9a-z_-]+)/os/}{/updates/$1/$2/};
				sendautotype $u;
			}
			sendkey "alt-p"; sleep 2; # enable proxy checkbox
			sendkey "alt-r"; # select proxy URL field
			sendautotype "http://$ENV{HTTPPROXY}";
			sleep 2;
			sendkey "alt-o"; sleep 2;
			waitstillimage;
			if($n==1) {sendkey "down"; sendkey "down";} # select Updates repo
		}
	}
	sendkey "alt-n"; # accept
	sleep 10;
	sendkey "alt-c"; # cOntinue in spite of missing deps
	# this starts install
}

1;
