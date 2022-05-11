# Copyright 2018 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package OpenQA::Qemu::ControllerConf;
use Mojo::Base 'OpenQA::Qemu::MutParams', -signatures;

use OpenQA::Qemu::DriveController;
use List::Util 'first';

has _controllers => sub ($self) { [] };

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

sub has_state ($self) { scalar(@{$self->_controllers}) }

1;
