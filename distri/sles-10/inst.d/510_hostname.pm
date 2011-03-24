use base "basetest";
use strict;
use bmwqemu;

sub run()
{ my $self=shift;
        # Hostname
        sendkey "alt-h";
        sendautotype "susetest\t";
        sendautotype "zq1.de";
	$self->take_screenshot;
        sendkey "alt-n";
        
        # network conf
        sleep 28; # longwait Net|DSL|Modem
        waitidle;
}

1;
