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
our @EXPORT = qw/mutex_create mutex_lock mutex_unlock mutex_try_lock/;

require bmwqemu;
use mmapi qw/api_call/;

sub mutex_lock($;$) {
    my ($name, $where) = @_;
    bmwqemu::diag("mutex lock '$name'");
    while (1) {
        my $param = {action => 'lock'};
        $param->{where} = $where if $where;
        my $res = api_call('post', "mutex/$name", $param)->code;
        return 1 if ($res == 200);

        bmwqemu::mydie "mutex lock '$name': lock owner already finished" if $res == 410;

        if ($res != 409) {
            bmwqemu::fctwarn("Unknown return code $res for lock api");
            return 0;
        }

        bmwqemu::diag("mutex lock '$name' unavailable, sleeping 5s");
        sleep(5);
    }
}

sub mutex_try_lock($;$) {
    my ($name, $where) = @_;
    bmwqemu::diag("mutex try lock '$name'");
    my $param = {action => 'lock'};
    $param->{where} = $where if $where;
    my $res = api_call('post', "mutex/$name", $param)->code;
    return 1 if ($res == 200);

    die "mutex lock '$name': lock owner already finished" if $res == 410;

    if ($res != 409) {
        bmwqemu::fctwarn("Unknown return code $res for lock api");
    }
    return 0;
}

sub mutex_unlock($) {
    my ($name) = @_;

    bmwqemu::diag("mutex unlock '$name'");
    my $res = api_call('post', "mutex/$name", {action => 'unlock'})->code;
    return 1 if ($res == 200);
    bmwqemu::fctwarn("Unknown return code $res for lock api") if ($res != 409);
    return 0;
}

sub mutex_create($) {
    my ($name) = @_;

    bmwqemu::diag("mutex create '$name'");
    my $res = api_call('post', "mutex", {name => $name})->code;
    return 1 if ($res == 200);
    bmwqemu::fctwarn("Unknown return code $res for lock api") if ($res != 409);
    return 0;
}

1;
