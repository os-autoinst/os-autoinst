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

package consoles::ttyConsole;

use Mojo::Base -strict, -signatures;
use autodie ':all';

use base 'consoles::console';

require IPC::System::Simple;

sub trigger_select ($self) {
    $self->screen->send_key({key => $self->console_key});
    return;
}

sub screen ($self) {
    return $self->backend->console('sut');
}

1;
