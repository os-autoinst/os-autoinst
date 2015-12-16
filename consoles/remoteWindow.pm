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

use strict;
use warnings;
require IPC::System::Simple;
use autodie qw(:all);

sub activate() {
    my ($self, $testapi_console, $console_args) = @_;

    my ($window_name) = $console_args->{window_name};
    # This will only work on a remote X display, i.e. when
    # current_console->{DISPLAY} is set for the current console.
    # There is only one DISPLAY which we can do this with: the
    # local-Xvnc aka worker one
    # FIXME: verify the first in the list of window ids with the same name is the mothership
    my $display   = $self->{DISPLAY};
    my $window_id = qx"DISPLAY=$display xdotool search --sync --limit 1 $window_name";
    die if $?;
    $self->{window_id} = $window_id;
}

sub disable() {
    my ($self)    = @_;
    my $window_id = $self->{window_id};
    my $display   = $self->{consoles}->{worker}->{DISPLAY};
    system("DISPLAY=$display xdotool windowkill $window_id");
}
sub select() {
    my ($self) = @_;
    $self->_activate_window();
}

1;
