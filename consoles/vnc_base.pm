# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package consoles::vnc_base;

use Mojo::Base 'consoles::video_base', -signatures;
use consoles::VNC;
use Time::HiRes qw(usleep);

use bmwqemu ();

# speed limit: 30 keys per second
use constant VNC_TYPING_LIMIT_DEFAULT => consoles::video_base::TYPING_LIMIT_DEFAULT;

sub screen ($self) { $self }

sub disable ($self) {
    close($self->{vnc}->socket) if ($self->{vnc} && $self->{vnc}->socket);
    $self->{vnc} = undef;
}

sub get_last_mouse_set ($self, $args) { $self->{mouse} }

sub disable_vnc_stalls ($self) {
    return unless $self->{vnc};
    $self->{vnc}->check_vnc_stalls(0);
}

sub connect_remote ($self, $args) {
    $self->{mouse} = {x => -1, y => -1};

    die "Need parameters 'hostname' and 'port'" unless $args->{hostname} && $args->{port};
    bmwqemu::diag "Establishing VNC connection to $args->{hostname}:$args->{port}";
    $self->{vnc} = consoles::VNC->new($args);
    $self->{vnc}->login($args->{connect_timeout});
    return $self->{vnc};
}

sub request_screen_update ($self, $args = undef) {
    return unless $self->{vnc};
    # drain the VNC socket before polling for a new update
    $self->{vnc}->update_framebuffer();
    $self->{vnc}->send_update_request($args ? $args->{incremental} : undef);
    return;
}

sub current_screen ($self) {
    return unless $self->{vnc};

    unless ($self->{vnc}->_framebuffer) {
        # No _framebuffer yet.  First connect?  Tickle vnc server to
        # get it filled.
        $self->request_screen_update();
        # wait long enough, new Xvnc on tumbleweed choked on shorter
        # waits after first login

        # As an alternative to sleeping we could potentially try to instead
        # loop update_framebuffer until _framebuffer in connect_remote
        usleep(50_000);
    }

    $self->{vnc}->update_framebuffer();
    return unless $self->{vnc}->_framebuffer;
    return $self->{vnc}->_framebuffer;
}

sub _typing_limit () { $bmwqemu::vars{VNC_TYPING_LIMIT} // VNC_TYPING_LIMIT_DEFAULT || 1 }

sub send_key_event ($self, $key, $press_release_delay) {
    $self->{vnc}->map_and_send_key($key, undef, $press_release_delay);
}

sub hold_key ($self, $args) {
    $self->{vnc}->map_and_send_key($args->{key}, 1, 1 / VNC_TYPING_LIMIT_DEFAULT);
    $self->backend->run_capture_loop(.2);
    return {};
}

sub release_key ($self, $args) {
    $self->{vnc}->map_and_send_key($args->{key}, 0, 1 / VNC_TYPING_LIMIT_DEFAULT);
    $self->backend->run_capture_loop(.2);
    return {};
}

sub mouse_width ($self) { return $self->{vnc}->width; }
sub mouse_height ($self) { return $self->{vnc}->height; }

sub mouse_move_to ($self, $x, $y) {
    $self->{vnc}->mouse_move_to($x, $y);
}

sub mouse_absolute ($self) {
    $self->{vnc}->absolute;
}

sub mouse_button ($self, $args) {
    my $button = $args->{button};
    my $bstate = $args->{bstate};
    my $mask = {left => $bstate, right => $bstate << 2, middle => $bstate << 1}->{$button} // 0;
    bmwqemu::diag "pointer_event $mask $self->{mouse}->{x}, $self->{mouse}->{y}";
    $self->{vnc}->send_pointer_event($mask, $self->{mouse}->{x}, $self->{mouse}->{y});
    return {};
}

1;
