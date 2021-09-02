# Copyright © 2020 SUSE LLC
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

package backend::null;

use Mojo::Base -strict;

use base 'backend::baseclass';

sub new { shift->SUPER::new }

sub do_start_vm { {} }

sub do_stop_vm { }

sub run_cmd { }

sub can_handle { }

sub is_shutdown { 1 }

sub stop_serial_grab { }

1;
