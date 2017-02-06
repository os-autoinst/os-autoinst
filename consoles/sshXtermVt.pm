# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2015 SUSE LLC
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

package consoles::sshXtermVt;
use base 'consoles::localXvnc';
use strict;
use warnings;
use testapi 'get_var';
require IPC::System::Simple;
use autodie ':all';
use File::Which;
use OpenQA::Log;

sub fullscreen {
    my ($self, $args) = @_;

    my $display     = $self->{DISPLAY};
    my $window_name = $args->{window_name};

    my $xdotool = which "xdotool";
    die "Missing 'xdotool'" unless $xdotool;
    # search for YaST Window and grab the id
    my $window_id = qx"DISPLAY=$display $xdotool search --sync --limit 1 --name $window_name";
    $window_id =~ s/\D//g;

    # resize and move window to fit in icewm
    system("DISPLAY=$display $xdotool windowsize $window_id 100% 100%");
    system("DISPLAY=$display $xdotool windowmove $window_id 0 0");
}

sub activate {
    my ($self) = @_;

    # start Xvnc
    $self->SUPER::activate;

    my $testapi_console = $self->{testapi_console};
    my $ssh_args        = $self->{args};
    my $gui             = $self->{args}->{gui};

    my $hostname = $ssh_args->{hostname} || die('we need a hostname to ssh to');
    my $password = $ssh_args->{password} || $testapi::password;
    my $sshcommand = $self->sshCommand($hostname, $gui);
    my $display = $self->{DISPLAY};

    $sshcommand = "TERM=xterm " . $sshcommand;
    my $xterm_vt_cmd = which "xterm-console";
    die "Missing 'xterm-console'" unless $xterm_vt_cmd;
    my $window_name = "ssh:$testapi_console";
    eval { system("DISPLAY=$display $xterm_vt_cmd -title $window_name -e bash -c '$sshcommand' & echo \$!") };
    if (my $E = $@) {
        die "cant' start xterm on $display (err: $! retval: $?)";
    }

    # FIXME: assert_screen('xterm_password');
    sleep 3;
    $self->type_string({text => $password . "\n"});
}

1;
