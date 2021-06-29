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

package OpenQA::Qemu::ControllerConf;
use Mojo::Base 'OpenQA::Qemu::MutParams', -signatures;

use OpenQA::Qemu::DriveController;
use List::Util 'first';

has _controllers => sub { return []; };

sub add_controller ($self, $model, $id) {
    my $dc = OpenQA::Qemu::DriveController->new()
      ->model($model)
      ->id($id);

    push(@{$self->_controllers}, $dc);
    return $dc;
}

sub gen_cmdline ($self) { map { $_->gen_cmdline() } @{$self->_controllers}, }

sub get_controller ($self, $id) { first { $_->id eq $id } @{$self->_controllers} }

sub get_controllers ($self, $type) { grep { $_->model =~ $type } @{$self->_controllers} }

sub to_map ($self) {
    my @controllers = map { $_->_to_map } @{$self->_controllers};
    return {controllers => \@controllers};
}

sub from_map ($self, $map) {
    for my $c (@{$map->{controllers}}) {
        $self->add_controller($c->{model}, $c->{id});
    }
}

sub has_state { scalar(@{shift->_controllers}) }

1;
