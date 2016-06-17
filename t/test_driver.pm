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

# This provides a mean to test things without requiring a real backend
package t::test_driver;

use strict;
use Carp;

sub new {
    my $class = shift;

    my $hash;
    $hash->{cmds}      = [];
    $hash->{exit_code} = 0;
    return bless $hash, $class;
}

sub _forward {
    my ($self, $args) = @_;
    push(@{$self->{cmds}}, (caller(1))[3], $args);
}

sub type_string { _forward(@_) }
sub send_key    { _forward(@_) }
sub wait_serial {
    _forward(@_);
    my $self = shift;
    my $r    = $self->{cmds}->[-1]->{regexp} =~ s/\\d\+/$self->{exit_code}/r;
    $r =~ s/\d\+/$self->{exit_code}/;
    return {
        matched => 1,
        string  => $r,    # the input regex we want to return as found
    };
}

sub mock_exit_code {
    my ($self, $code) = @_;
    $self->{exit_code} = $code;
}

1;
