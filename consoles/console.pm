# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2021 SUSE LLC
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

=head2 consoles::console

Base class for consoles. That is, 'user' interfaces between os-autoinst and
the SUT which are independant of the backend (e.g. QEMU, IPMI). Consoles are
used to match needles against the GUI and send key presses (e.g. VNC) or
communicate with the shell using text (e.g. virtio_terminal).

Consoles should implement disable and reset if necessary as well as a number
of other functions. See vnc_base and virtio_terminal to see how this works.

=cut

package consoles::console;

use Mojo::Base -strict, -signatures;
use autodie ':all';
use testapi 'check_var';

require IPC::System::Simple;
use Class::Accessor 'antlers';

has backend => (is => "rw");

sub new ($class, $testapi_console, $args) {
    my $self = bless({class => $class}, $class);
    $self->{testapi_console} = $testapi_console;
    $self->{args}            = $args;
    $self->{activated}       = 0;
    $self->init;
    return $self;
}

sub init ($self) {
    # Special keys like Ctrl-Alt-Fx are not passed to the VM by xfreerdp.
    # That means switch from graphical to console is not possible on Hyper-V.
    $self->{console_hotkey} = check_var('VIRSH_VMM_FAMILY', 'hyperv') ? 'alt-f' : 'ctrl-alt-f';
}

# SUT was e.g. rebooted
sub reset ($self) {
    $self->{activated} = 0;
    return;
}

sub screen ($self) {
    die "screen needs to be implemented in subclasses - $self->{class} does not\n";
    return;
}

# to be overloaded
sub trigger_select { }

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

sub activate { }

sub is_serial_terminal { 0 }

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
