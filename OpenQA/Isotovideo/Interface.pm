# Copyright © 2018-2021 SUSE LLC
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

package OpenQA::Isotovideo::Interface;

use Mojo::Base -strict, -signatures;

# version of the test API and the API relevant to the worker
# -> increment on every change of such APIs
# -> never move that variable to another place (when refactoring)
#    because it may be accessed by the tests itself
our $version = 23;

# major version of the (web socket) API relevant to the developer mode
# -> increment when making non-backward compatible changes to that API
our $developer_mode_major_version = 1;
# minor version of the (web socket) API relevant to the developer mode
# -> reset to 0 when making non-backward compatible changes to that API
# -> increment when making backward compatible changes to that API
our $developer_mode_minor_version = 1;

1;
