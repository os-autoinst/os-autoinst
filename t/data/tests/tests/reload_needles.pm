# Copyright (C) 2017 SUSE LLC
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

use 5.018;
use Mojo::Base -strict;

use base 'basetest';

use testapi;

use Data::Dumper;

sub run {
    # this is the default, but to test set_var without argument
    set_var('VERSION', '1');
    type_string "echo HALLO\n";
    my $ret = assert_screen 'no-importa';
    die 'Should see v1' unless $ret->{needle}->{name} eq 'no-importa-v1';

    set_var('VERSION', '2', reload_needles => 1);
    $ret = assert_screen 'no-importa';
    die 'Should see v2' unless $ret->{needle}->{name} eq 'no-importa-v2';

}

1;
