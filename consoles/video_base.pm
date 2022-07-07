# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package consoles::video_base;

use Mojo::Base 'consoles::network_console', -signatures;
use bmwqemu ();

# speed limit: 30 keys per second
use constant TYPING_LIMIT_DEFAULT => 30;

# magic default from testapi.pm
use constant DEFAULT_MAX_INTERVAL => 250;

my $CHARMAP = {
    "-" => 'minus',
    "\t" => 'tab',
    "\n" => 'ret',
    "\b" => 'backspace',
    "\e" => 'esc',
    " " => 'spc',
};

sub screen ($self) { $self }

sub get_last_mouse_set ($self, $args) { $self->{mouse} }

sub _typing_limit () { $bmwqemu::vars{TYPING_LIMIT} // TYPING_LIMIT_DEFAULT || 1 }

sub send_key_event ($key, $press_release_delay) { }

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
    if (($args->{max_interval} // DEFAULT_MAX_INTERVAL) < DEFAULT_MAX_INTERVAL) {
        # according to 	  git grep "type_string.*, *[0-9]"  on
        #   https://github.com/os-autoinst/os-autoinst-distri-opensuse,
        # typical max_interval values are
        #   4ish:  veeery slow
        #   15ish: slow
        $seconds_per_keypress += 1 / sqrt($args->{max_interval});
    }

    for my $letter (split("", $args->{text})) {
        next if ($letter eq "\r");
        $letter = $CHARMAP->{$letter} || $letter;
        # 25% is spent hitting the key, 25% releasing it, 50% searching the next key
        $self->send_key_event($letter, $seconds_per_keypress * 0.25);
        $self->{backend}->run_capture_loop($seconds_per_keypress * 0.5);
    }
    return {};
}

sub send_key ($self, $args) {
    # send_key rate must be limited to take into account VNC_TYPING_LIMIT- poo#55703
    # map_and_send_key: do not be faster than default
    my $press_release_delay = 1 / _typing_limit;

    $self->send_key_event($args->{key}, $press_release_delay);
    $self->backend->run_capture_loop(.2);
    return {};
}

sub mouse_move_to ($self, $x, $y) { }

# those refer to emulated tablet resolution, which (theoretically) might be
# different than the screen
sub mouse_width ($self) { $self->{backend}->{xres}; }
sub mouse_height ($self) { $self->{backend}->{yres}; }

sub mouse_absolute ($self) { return 1; }

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
        $delta = -5 if $x > $self->mouse_width / 2;
        $self->mouse_move_to($x + $delta, $y);
    }

    $self->{mouse}->{x} = $x;
    $self->{mouse}->{y} = $y;

    bmwqemu::diag "mouse_move $x, $y";
    $self->mouse_move_to($x, $y);
    return;
}

sub mouse_hide ($self, $args) {
    $args->{border_offset} //= 0;

    my $x = $self->mouse_width - 1;
    my $y = $self->mouse_height - 1;

    if (defined $args->{border_offset}) {
        my $border_offset = int($args->{border_offset});
        $x -= $border_offset;
        $y -= $border_offset;
    }

    $self->_mouse_move($x, $y);
    return {absolute => $self->mouse_absolute};
}

sub mouse_set ($self, $args) {
    die "Need x/y arguments" unless (defined $args->{x} && defined $args->{y});
    $self->_mouse_move(int($args->{x}), int($args->{y}));
    return {};
}


1;
