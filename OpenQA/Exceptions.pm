# Copyright © 2016-2021 SUSE LLC
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

package OpenQA::Exceptions;

use Mojo::Base -strict, -signatures;

use Exception::Class (
    'OpenQA::Exception::InternalException' => {
        description => 'internal errors not for the user'
    },
    'OpenQA::Exception::FailedNeedle' => {
        description => 'assert_screen failed',
        fields      => 'tags',
    },
    'OpenQA::Exception::VNCProtocolError' => {
        description => 'VNC Server interrupted connection'
    },
    'OpenQA::Exception::VNCSetupError' => {
        description => 'Failed to connect to VNC Server'
    },
    'OpenQA::Exception::SSHConnectionError' => {
        description => 'Failed to connect to SSH Server'
    },
    'OpenQA::Exception::ConsoleReadError' => {
        description => 'Failed to receive data from console'
    },
);

1;
