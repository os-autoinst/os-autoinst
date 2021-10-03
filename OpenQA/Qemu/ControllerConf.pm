# Copyright 2018 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

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
