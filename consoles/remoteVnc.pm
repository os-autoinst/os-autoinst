# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2020 SUSE LLC
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

package consoles::remoteVnc;

use Mojo::Base -strict;

use base 'consoles::vnc_base';

use testapi 'get_var';

sub init {
    my ($self) = @_;
    $self->{name} = 'remote-vnc';
}

sub activate {
    my ($self, $testapi_console, $console_args) = @_;

    return $self->SUPER::activate(
        $testapi_console,
        {
            hostname => get_var("PARMFILE")->{Hostname},
            password => get_var("DISPLAY")->{PASSWORD},
            port     => 5901,
            ikvm     => 0,
        });
}

# override
sub select { }

1;
