#!/usr/bin/perl -w
use strict;
use base "serverstep";
use bmwqemu;


sub run()
{
    my $self=shift;

    # Install apache2
    script_sudo("zypper -n -q in mysql");
    waitidle(10);

    # After installation, mysql is disabled
    script_sudo("systemctl status mysql.service | tee /dev/ttyS0 -");
    waitidle(5);
    die unless waitserial(".*inactive.*", 2);

    # Now must be enabled
    script_sudo("systemctl start mysql.service");
    script_sudo("systemctl status mysql.service | tee /dev/ttyS0 -");
    waitidle(5);
    die if waitserial(".*Syntax error.*", 2);    

    $self->check_screen;
}

1;
