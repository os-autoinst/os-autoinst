package backend::svirt;
use strict;
use base ('backend::baseclass');

use IO::Select;

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

    # truncate the serial file
    open(my $sf, '>', $self->{serialfile});
    close($sf);

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

    $self->stop_serial_grab;
    return {};
}

my $run_serial_grab;

# open another ssh connection to grab the serial console
sub start_serial_grab {
    my ($self, $name) = @_;

    $run_serial_grab = 1;

    $self->{serial} = Net::SSH2->new;
    $self->{serial}->connect($bmwqemu::vars{VIRSH_HOSTNAME});
    $self->{serial}->auth_password('root', $bmwqemu::vars{VIRSH_PASSWORD});
    my $chan = $self->{serial}->channel();
    $self->{serial_chan} = $chan;
    $chan->blocking(0);
    $chan->pty(1);
    $chan->exec('virsh console ' . $name);
    $self->{select}->add($self->{serial}->sock);
}

sub check_socket {
    my ($self, $fh, $write) = @_;

    if ($self->{serial} && $self->{serial}->sock == $fh) {
        my $chan = $self->{serial_chan};
        my $line = <$chan>;
        if ($line) {
            print $line;
            open(my $serial, '>>', $self->{serialfile});
            print $serial $line;
            close($serial);
        }
        return 1;
    }
    return $self->SUPER::check_socket($fh, $write);
}

sub stop_serial_grab {
    my ($self) = @_;
    $self->{select}->remove($self->{serial}->sock);
    $self->{serial}->disconnect;
    $self->{serial} = undef;
    return;
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
