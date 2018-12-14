# Copyright © 2018 SUSE LLC
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
use Mojo::Base 'OpenQA::Qemu::MutParams';

use OpenQA::Qemu::DriveController;
use List::Util 'first';

has _controllers => sub { return []; };

sub add_controller {
    my ($self, $model, $id) = @_;
    my $dc = OpenQA::Qemu::DriveController->new()
      ->model($model)
      ->id($id);

    push(@{$self->_controllers}, $dc);
    return $dc;
}

sub gen_cmdline {
    my $self = shift;

    return map { $_->gen_cmdline() } @{$self->_controllers},;
}

sub get_controller {
    my ($self, $id) = @_;

    return first { $_->id eq $id } @{$self->_controllers};
}

sub get_controllers {
    my ($self, $type) = @_;

    return grep { $_->model =~ $type } @{$self->_controllers};
}

sub to_map {
    my $self        = shift;
    my @controllers = map { $_->_to_map } @{$self->_controllers};

    return {controllers => \@controllers};
}

sub from_map {
    my ($self, $map) = @_;

    for my $c (@{$map->{controllers}}) {
        $self->add_controller($c->{model}, $c->{id});
    }
}

sub has_state {
    return scalar(@{shift->_controllers});
}

1;
