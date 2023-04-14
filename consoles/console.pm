# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

=head2 consoles::console

Base class for consoles. That is, 'user' interfaces between os-autoinst and
the SUT which are independent of the backend (e.g. QEMU, IPMI). Consoles are
used to match needles against the GUI and send key presses (e.g. VNC) or
communicate with the shell using text (e.g. virtio_terminal).

Consoles should implement disable and reset if necessary as well as a number
of other functions. See vnc_base and virtio_terminal to see how this works.

=cut

package consoles::console;

use Mojo::Base -base, -signatures;
use autodie ':all';

require IPC::System::Simple;

has 'backend';

sub new ($class, $testapi_console, $args) {
    my $self = bless({class => $class}, $class);
    $self->{testapi_console} = $testapi_console;
    $self->{args} = $args;
    $self->{activated} = 0;
    $self->init;
    return $self;
}

sub init ($self) {
    # Special keys like Ctrl-Alt-Fx are not passed to the VM by xfreerdp.
    # That means switch from graphical to console is not possible on Hyper-V.
    $self->{console_hotkey} = ($bmwqemu::vars{VIRSH_VMM_FAMILY} // '') eq 'hyperv' ? 'alt-f' : 'ctrl-alt-f';
}

# SUT was e.g. rebooted
sub reset ($self) {
    $self->{activated} = 0;
    return;
}

sub screen ($self) { die "screen needs to be implemented in subclasses - $self->{class} does not\n" }

# to be overloaded
sub trigger_select ($self) { }

sub select ($self) {
    my $activated;
    if (!$self->{activated}) {
        my $ret = $self->activate;
        # undef on success
        return $ret if $ret;
        $self->{activated} = 1;
        $activated = 1;
    }
    $self->trigger_select;
    return $activated;
}

sub activate ($self) { }

sub is_serial_terminal ($self) { 0 }

sub set_args ($self, %args) {
    my $my_args = $self->{args};
    $self->{args}->{$_} = $args{$_} for (keys %args);
    # no need to send changes to right process; console proxy already takes care
    # that this method is called in the right process
}

sub set_tty ($self, $tty) {
    $self->{args}->{tty} = $tty;
    # no need to send changes to right process; console proxy already takes care
    # that this method is called in the right process
}

sub console_key ($self) {
    return undef unless $self->{console_hotkey} && $self->{args}->{tty};
    return $self->{console_hotkey} . $self->{args}->{tty};
}

1;
