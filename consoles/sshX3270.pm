# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2015 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package consoles::sshX3270;

use Mojo::Base -strict;

use base 'consoles::localXvnc';

use testapi 'get_var';

sub activate {
    my ($self) = @_;

    my $sshcommand  = $self->sshCommand('root', get_var("PARMFILE")->{Hostname});
    my $display     = $self->{backend}->{consoles}->{worker}->{DISPLAY};
    my $sshpassword = $testapi::password;

    $sshcommand = "TERM=vt100 " . $sshcommand;
    my $console_info = $self->new_3270_console({vnc_backend => $self});
    # do ssh connect
    my $s3270 = $console_info->{console};
    $s3270->send_3270("Connect(\"-e $sshcommand\")");
    # wait for 10 seconds for password prompt
    for my $i (-9 .. 0) {
        $s3270->send_3270("Snap");
        my $r  = $s3270->send_3270("Snap(Ascii)");
        my $co = $r->{command_output};
        CORE::say bmwqemu::pp($co);
        last if grep { /[Pp]assword:/ } @$co;
        die "ssh password prompt timeout" unless $i;
        sleep 1;
    }
    $s3270->send_3270("String(\"$sshpassword\")");
    $s3270->send_3270("ENTER");
}

1;
