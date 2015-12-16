package backend::svirt;
use strict;
use base ('backend::baseclass');

# this is a fake backend to some extend. We don't start VMs, but provide ssh access
# to a libvirt running host (KVM for System Z in mind)

use testapi qw/get_var/;

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new;
    die "configure WORKER_HOSTNAME e.g. in workers.ini" unless get_var('WORKER_HOSTNAME');
    return $self;
}


# we don't do anything actually
sub do_start_vm {
    my ($self) = @_;

    my $ssh = $testapi::distri->add_console(
        'svirt',
        'ssh-virtsh',
        {
            hostname => $bmwqemu::vars{VIRSH_HOSTNAME},
            password => $bmwqemu::vars{VIRSH_PASSWORD},
        });
    $ssh->backend($self);
    $self->select_console({testapi_console => 'svirt'});

    # remove backend.crashed
    $self->unlink_crash_file;
    return {};
}

sub do_stop_vm {
    my ($self) = @_;

    return {};
}

sub do_loadvm {
    my ($self, $args) = @_;
    die "virsh snapshot handling not yet implemented";
}

sub status {
    my ($self) = @_;
    return;
}

1;

# vim: set sw=4 et:
