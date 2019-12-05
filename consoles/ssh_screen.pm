# Copyright © 2019 SUSE LLC
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

package consoles::ssh_screen;

use Mojo::Base 'consoles::serial_screen';
use Carp 'croak';

has ssh_connection => undef;
has ssh_channel    => undef;

sub new {
    my $class = shift;
    my $self  = bless @_ ? @_ > 1 ? {@_} : {%{$_[0]}} : {}, ref $class || $class;

    croak('Missing parameter ssh_connection') unless $self->ssh_connection;
    croak('Missing parameter ssh_channel')    unless $self->ssh_channel;

    return $self->SUPER::new($self->ssh_channel);
}

sub do_read
{
    my ($self, undef, %args) = @_;
    my $buffer = '';
    $args{timeout}  //= undef;    # wait till data is available
    $args{max_size} //= 2048;

    croak('We expect to get a none blocking SSH channel') if ($self->ssh_channel->blocking());
    my $stime = consoles::serial_screen::thetime();
    while (!$args{timeout} || (consoles::serial_screen::elapsed($stime) < $args{timeout})) {
        my $read = $self->ssh_channel->read($buffer, $args{max_size});
        if (defined($read)) {
            $_[1] = $buffer;
            return $read;
        }

        last if ($args{timeout} == 0);
        select(undef, undef, undef, 0.25);
    }
    return undef;
}
1;
