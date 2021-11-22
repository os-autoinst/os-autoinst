# Copyright 2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Helper class to use descriptive names for file descriptors within IO::Select

package OpenQA::NamedIOSelect;
use Mojo::Base -base, -signatures;
use IO::Select;
use Carp;

sub select ($self) { $self->{select_obj} //= IO::Select->new() }

sub names ($self) { $self->{names_hash} //= {} }

sub add ($self, $fd, $name = undef) {
    my $fd_nr = fileno $fd // $fd;
    if (!defined($name)) {
        my ($package, $filename, $line) = caller;
        $name = sprintf('NamedIOSelect::add(%d) called at %s:%d', $fd_nr, $filename, $line);
    }

    $self->names->{$fd_nr} = $name;
    $self->select->add($fd);
}

sub get_name ($self, $fd) {
    my $fd_nr = fileno $fd // $fd;
    return $self->names->{$fd_nr} // "Unknown fd($fd_nr)";
}

sub remove ($self, $fd) {
    delete $self->names->{fileno $fd // $fd};
    $self->select->remove($fd);
}

1;
