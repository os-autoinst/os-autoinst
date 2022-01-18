# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package consoles::vnc_base;

use Mojo::Base -strict, -signatures;

use base 'consoles::network_console';

use consoles::VNC;
use Time::HiRes qw(usleep);

use consoles::console qw(DEFAULT_MAX_INTERVAL);
use bmwqemu ();

# speed limit: 30 keys per second
use constant VNC_TYPING_LIMIT_DEFAULT => 30;

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

    bmwqemu::diag "Establishing VNC connection to $args->{hostname}:$args->{port}";
    $self->{vnc} = consoles::VNC->new($args);
    $self->{vnc}->login($args->{connect_timeout});
    return $self->{vnc};
}

sub request_screen_update ($self, @) {
    return unless $self->{vnc};
    # drain the VNC socket before polling for a new update
    $self->{vnc}->update_framebuffer();
    $self->{vnc}->send_update_request();
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

sub type_string ($self, $args) {
    my $seconds_per_keypress = 1 / _typing_limit;

    # further slow down if being asked for.

    # Note: the intended use of max_interval is the bootloader. The bootloader
    # prompt drops characters when typing quickly. This problem mostly occurs
    # in the bootloader. Humans notice because they look at the screen while
    # typing. So this loop should be replaced by some true 'looking at the
    # screen while typing', e.g. waiting for no more screen updates 'in the
    # right area'.  For now, just waiting is good enough: The slow-down only
    # affects the bootloader sequence.
    if (($args->{max_interval} // consoles::console::DEFAULT_MAX_INTERVAL) < consoles::console::DEFAULT_MAX_INTERVAL) {
        # according to 	  git grep "type_string.*, *[0-9]"  on
        #   https://github.com/os-autoinst/os-autoinst-distri-opensuse,
        # typical max_interval values are
        #   4ish:  veeery slow
        #   15ish: slow
        $seconds_per_keypress = $seconds_per_keypress + 1 / sqrt($args->{max_interval});
    }

    for my $letter (split("", $args->{text})) {
        next if ($letter eq "\r");
        my $charmap = {
            "-" => 'minus',
            "\t" => 'tab',
            "\n" => 'ret',
            "\b" => 'backspace',
            "\e" => 'esc'
        };
        $letter = $charmap->{$letter} || $letter;
        # 25% is spent hitting the key, 25% releasing it, 50% searching the next key
        $self->{vnc}->map_and_send_key($letter, undef, $seconds_per_keypress * 0.25);
        $self->{backend}->run_capture_loop($seconds_per_keypress * 0.5);
    }
    return {};
}

sub send_key ($self, $args) {
    # send_key rate must be limited to take into account VNC_TYPING_LIMIT- poo#55703
    # map_and_send_key: do not be faster than default
    my $press_release_delay = 1 / _typing_limit;

    $self->{vnc}->map_and_send_key($args->{key}, undef, $press_release_delay);
    $self->backend->run_capture_loop(.2);
    return {};
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

sub _mouse_move ($self, $x, $y) {
    die "need parameter \$x and \$y" unless (defined $x and defined $y);

    if ($self->{mouse}->{x} == $x && $self->{mouse}->{y} == $y) {
        # in case the mouse is moved twice to the same position
        # (e.g. in case of duplicated mouse_hide), we need to wiggle the
        # mouse a bit to avoid qemu ignoring the repositioning
        # because the SUT might have moved the mouse itself and we
        # need to make sure the mouse is really where expected
        my $delta = 5;
        # move it to the left in case the mouse is right
        $delta = -5 if $x > $self->{vnc}->width / 2;
        $self->{vnc}->mouse_move_to($x + $delta, $y + $delta);
    }

    $self->{mouse}->{x} = $x;
    $self->{mouse}->{y} = $y;

    bmwqemu::diag "mouse_move $x, $y";
    $self->{vnc}->mouse_move_to($x, $y);
    return;
}

sub mouse_hide ($self, $args) {
    $args->{border_offset} //= 0;

    my $x = $self->{vnc}->width - 1;
    my $y = $self->{vnc}->height - 1;

    if (defined $args->{border_offset}) {
        my $border_offset = int($args->{border_offset});
        $x -= $border_offset;
        $y -= $border_offset;
    }

    $self->_mouse_move($x, $y);
    return {absolute => $self->{vnc}->absolute};
}

sub mouse_set ($self, $args) {
    die "Need x/y arguments" unless (defined $args->{x} && defined $args->{y});
    $self->_mouse_move(int($args->{x}), int($args->{y}));
    return {};
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
