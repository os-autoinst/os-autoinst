# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package consoles::video_base;

use Mojo::Base 'consoles::network_console', -signatures;
use consoles::console qw(DEFAULT_MAX_INTERVAL);
use bmwqemu ();

# speed limit: 30 keys per second
use constant TYPING_LIMIT_DEFAULT => 30;

sub screen ($self) { $self }

sub get_last_mouse_set ($self, $args) { $self->{mouse} }

sub _typing_limit () { $bmwqemu::vars{TYPING_LIMIT} // TYPING_LIMIT_DEFAULT || 1 }

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
        $self->{console}->map_and_send_key($letter, undef, $seconds_per_keypress * 0.25);
        $self->{backend}->run_capture_loop($seconds_per_keypress * 0.5);
    }
    return {};
}

sub send_pointer_event ($self, $mask) {}

sub mouse_button ($self, $args) {
    my $button = $args->{button};
    my $bstate = $args->{bstate};
    my $mask = {left => $bstate, right => $bstate << 2, middle => $bstate << 1}->{$button} // 0;
    bmwqemu::diag "pointer_event $mask $self->{mouse}->{x}, $self->{mouse}->{y}";
    $self->send_pointer_event($mask);
    return {};
}

1;
