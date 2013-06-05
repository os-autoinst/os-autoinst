#!/usr/bin/perl -w
use strict;
use base "serverstep";
use bmwqemu;


sub run()
{
    my $self=shift;

    # Install apache2
    script_sudo("zypper -n -q in apache2");
    waitidle(10);
    $self->check_screen;

    # After installation, apache2 is disabled
    script_sudo("systemctl status apache2.service | tee /dev/ttyS0 -");
    waitidle(5);
    die unless waitserial(".*disable.*", 2);

    # Now must be enabled
    script_sudo("systemctl start apache2.service");
    script_sudo("systemctl status apache2.service | tee /dev/ttyS0 -");
    waitidle(5);
    die if waitserial(".*Syntax error.*", 2);    
}

1;
