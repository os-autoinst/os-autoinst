# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package consoles::spice_base;

use Mojo::Base 'consoles::video_base', -signatures;
use consoles::SPICE;
use Time::HiRes qw(usleep);

use bmwqemu ();

use constant SPICE_TYPING_LIMIT_DEFAULT => consoles::video_base::TYPING_LIMIT_DEFAULT;

sub disable ($self) {
    if ($self->{vnc}) {
        $self->{vnc}->socket->close if $self->{vnc}->socket;
        $self->{vnc} = undef;
    }
}

sub connect_remote ($self, $args) {
    $self->{mouse} = {x => -1, y => -1};

    die q{Need parameters 'hostname' and 'port'} unless $args->{hostname} && $args->{port};
    bmwqemu::diag "Establishing SPICE connection via bridge to $args->{hostname}:$args->{port}";
    $self->{vnc} = consoles::SPICE->new($args);
    $self->{vnc}->login($args->{connect_timeout});
    return $self->{vnc};
}

sub request_screen_update ($self, $args = undef) {
    return unless $self->{vnc};
    $self->{vnc}->update_framebuffer();
    return;
}

sub current_screen ($self) {
    return undef unless $self->{vnc};

    unless ($self->{vnc}->_framebuffer) {
        $self->request_screen_update();
        usleep(50_000);
    }

    $self->{vnc}->update_framebuffer();
    return undef unless $self->{vnc}->_framebuffer;
    return $self->{vnc}->_framebuffer;
}

sub send_key_event ($self, $key, $delay) {
    die 'No SPICE connection available' unless $self->{vnc};
    $self->{vnc}->map_and_send_key($key, undef, $delay);
}

sub hold_key ($self, $args) {
    die 'No SPICE connection available' unless $self->{vnc};
    $self->{vnc}->map_and_send_key($args->{key}, 1, 1 / SPICE_TYPING_LIMIT_DEFAULT);
    $self->backend->run_capture_loop(.2);
    return {};
}

sub release_key ($self, $args) {
    die 'No SPICE connection available' unless $self->{vnc};
    $self->{vnc}->map_and_send_key($args->{key}, 0, 1 / SPICE_TYPING_LIMIT_DEFAULT);
    $self->backend->run_capture_loop(.2);
    return {};
}

sub mouse_width ($self) { return $self->{vnc}->width; }
sub mouse_height ($self) { return $self->{vnc}->height; }

sub mouse_move_to ($self, $x, $y) {
    $self->{mouse} = {x => $x, y => $y};
    $self->{vnc}->mouse_move_to($x, $y);
}

sub mouse_absolute ($self) {
    # SPICE defaults to absolute pointer
    return 1;
}

sub mouse_button ($self, $args) {
    my $button = $args->{button};
    my $bstate = $args->{bstate};
    my $mask = {left => $bstate, right => $bstate << 2, middle => $bstate << 1}->{$button} // 0;
    bmwqemu::diag "pointer_event $mask $self->{mouse}->{x}, $self->{mouse}->{y}";
    die 'No SPICE connection available' unless $self->{vnc};
    $self->{vnc}->send_pointer_event($mask, $self->{mouse}->{x}, $self->{mouse}->{y});
    return {};
}

1;
