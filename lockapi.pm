# Copyright (c) 2015 SUSE LINUX GmbH, Nuernberg, Germany.
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

## synchronization API
package lockapi;

use strict;
use warnings;

use base qw/Exporter/;
our @EXPORT = qw/mutex_create mutex_lock mutex_unlock/;

require bmwqemu;
use mmapi qw/api_call/;

sub mutex_lock($) {
    my ($name) = @_;
    return _mutex_call('get', "mutex/lock/$name");
}

sub mutex_unlock($) {
    my ($name) = @_;
    return _mutex_call('get', "mutex/unlock/$name");
}

sub mutex_create($) {
    my ($name) = @_;
    return _mutex_call('post', "mutex/lock/$name");
}

sub _mutex_call($$) {
    my ($method, $action) = @_;
    while (1) {
        my $res = api_call($method, $action)->code;
        last if ($res == 200);
        bmwqemu::fctwarn("Unknown return code $res for lock api") if ($res != 409);
        bmwqemu::diag('mutex lock unavailable, sleeping 5s');
        sleep(5);
    }
    bmwqemu::fctres("mutex action successful");
}

1;
