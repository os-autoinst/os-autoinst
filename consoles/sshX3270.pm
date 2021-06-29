# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2021 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package consoles::sshX3270;

use Mojo::Base -strict, -signatures;

use base 'consoles::localXvnc';

use testapi 'get_var';

sub activate ($self) {
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
