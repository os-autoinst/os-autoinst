#!/usr/bin/perl -w

# this is an abstract class
package backend::helper::scancodes;
use strict;

our $keymap_kvm2usb = {
    #
    'esc'           => 0x76,
    '1'             => 0x16,
    '2'             => 0x1E,
    '3'             => 0x26,
    '3'             => 0x26,
    '4'             => 0x25,
    '5'             => 0x2E,
    '6'             => 0x36,
    '7'             => 0x3D,
    '8'             => 0x3E,
    '9'             => 0x46,
    '0'             => 0x45,
    'minus'         => 0x4E,
    'equal'         => 0x55,
    'backspace'     => 0x66,
    'tab'           => 0x0D,
    'q'             => 0x15,
    'w'             => 0x1D,
    'e'             => 0x24,
    'r'             => 0x2D,
    't'             => 0x2C,
    'y'             => 0x35,
    'u'             => 0x3C,
    'i'             => 0x43,
    'o'             => 0x44,
    'p'             => 0x4D,
    'bracket_left'  => 0x54,
    'bracket_right' => 0x5B,
    'ret'           => 0x5A,
    'ctrl'          => 0x14,
    'a'             => 0x1C,
    's'             => 0x1B,
    'd'             => 0x23,
    'f'             => 0x2B,
    'g'             => 0x34,
    'h'             => 0x33,
    'j'             => 0x3B,
    'k'             => 0x42,
    'l'             => 0x4B,
    'semicolon'     => 0x4C,
    'apostrophe'    => 0x52,
    'grave_accent'  => 0x0E,
    'shift'         => 0x12,
    'backslash'     => 0x5D,
    'z'             => 0x1A,
    'x'             => 0x22,
    'c'             => 0x21,
    'v'             => 0x2A,
    'b'             => 0x32,
    'n'             => 0x31,
    'm'             => 0x3A,
    'comma'         => 0x41,
    'dot'           => 0x49,
    'slash'         => 0x4A,
    'shift_r'       => 0x59,
    'asterisk'      => 0x7C,
    'alt'           => 0x11,
    'spc'           => 0x29,
    'caps_lock'     => 0x58,
    'f1'            => 0x05,
    'f2'            => 0x06,
    'f3'            => 0x04,
    'f4'            => 0x0C,
    'f5'            => 0x03,
    'f6'            => 0x0B,
    'f7'            => 0x83,
    'f8'            => 0x0A,
    'f9'            => 0x01,
    'f10'           => 0x09,
    'num_lock'      => 0x77,
    'kp_7'          => 0x6C,
    'kp_8'          => 0x75,
    'kp_9'          => 0x7D,
    'kp_subtract'   => 0x7B,
    'kp_4'          => 0x6B,
    'kp_5'          => 0x73,
    'kp_6'          => 0x74,
    'kp_add'        => 0x79,
    'kp_1'          => 0x69,
    'kp_2'          => 0x72,
    'kp_3'          => 0x7A,
    'kp_0'          => 0x70,
    'kp_decimal'    => 0x71,
    'sysrq'         => 0x84,
    '<'             => 0x61,
    'f11'           => 0x78,
    'f12'           => 0x07,

    # function keys
    'ctrl_r' => 0xE014,
    #
    'alt_r'  => 0xE011,
    'home'   => 0xE06C,
    'pgup'   => 0xE07D,
    'pgdn'   => 0xE07A,
    'end'    => 0xE069,
    'left'   => 0xE06B,
    'up'     => 0xE075,
    'down'   => 0xE072,
    'right'  => 0xE074,
    'insert' => 0xE070,
    'delete' => 0xE071,
    'menu'   => 0xE02F,
};

our $keymap_vbox = {
    #
    'esc'           => 0x01,
    '1'             => 0x02,
    '2'             => 0x03,
    '3'             => 0x04,
    '4'             => 0x05,
    '5'             => 0x06,
    '6'             => 0x07,
    '7'             => 0x08,
    '8'             => 0x09,
    '9'             => 0x0A,
    '0'             => 0x0B,
    'minus'         => 0x0C,
    'equal'         => 0x0D,
    'backspace'     => 0x0E,
    'tab'           => 0x0F,
    'q'             => 0x10,
    'w'             => 0x11,
    'e'             => 0x12,
    'r'             => 0x13,
    't'             => 0x14,
    'y'             => 0x15,
    'u'             => 0x16,
    'i'             => 0x17,
    'o'             => 0x18,
    'p'             => 0x19,
    'bracket_left'  => 0x1A,
    'bracket_right' => 0x1B,
    'ret'           => 0x1C,
    'ctrl'          => 0x1D,
    'a'             => 0x1E,
    's'             => 0x1F,
    'd'             => 0x20,
    'f'             => 0x21,
    'g'             => 0x22,
    'h'             => 0x23,
    'j'             => 0x24,
    'k'             => 0x25,
    'l'             => 0x26,
    'semicolon'     => 0x27,
    'apostrophe'    => 0x28,
    'grave_accent'  => 0x29,
    'shift'         => 0x2A,
    'backslash'     => 0x2B,
    'z'             => 0x2C,
    'x'             => 0x2D,
    'c'             => 0x2E,
    'v'             => 0x2F,
    'b'             => 0x30,
    'n'             => 0x31,
    'm'             => 0x32,
    'comma'         => 0x33,
    'dot'           => 0x34,
    'slash'         => 0x35,
    'shift_r'       => 0x36,
    'asterisk'      => 0x37,
    'alt'           => 0x38,
    'spc'           => 0x39,
    'caps_lock'     => 0x3A,
    'f1'            => 0x3B,
    'f2'            => 0x3C,
    'f3'            => 0x3D,
    'f4'            => 0x3E,
    'f5'            => 0x3F,
    'f6'            => 0x40,
    'f7'            => 0x41,
    'f8'            => 0x42,
    'f9'            => 0x43,
    'f10'           => 0x44,
    'num_lock'      => 0x45,
    'scroll_lock'   => 0x46,
    'kp_7'          => 0x47,
    'kp_8'          => 0x48,
    'kp_9'          => 0x49,
    'kp_subtract'   => 0x4A,
    'kp_4'          => 0x4B,
    'kp_5'          => 0x4C,
    'kp_6'          => 0x4D,
    'kp_add'        => 0x4E,
    'kp_1'          => 0x4F,
    'kp_2'          => 0x50,
    'kp_3'          => 0x51,
    'kp_0'          => 0x52,
    'kp_decimal'    => 0x53,
    'sysrq'         => 0x54,
    '?'             => 0x55,
    '<'             => 0x56,
    'f11'           => 0x57,
    'f12'           => 0x58,

    # function keys
    'ctrl_r' => 0x9D,
    'print'  => 0xB7,
    'alt_r'  => 0xB8,
    'home'   => 0xC7,
    'pgup'   => 0xC9,
    'pgdn'   => 0xD1,
    'end'    => 0xCF,
    'left'   => 0xCB,
    'up'     => 0xC8,
    'down'   => 0xD0,
    'right'  => 0xCD,
    'insert' => 0xD2,
    'delete' => 0xD3,
    'menu'   => 0xDD,
};

our $keymaps = {
    'kvm2usb' => $keymap_kvm2usb,
    'vbox'    => $keymap_vbox
};

sub init() {
    my $self = shift;
    $self->{'keymaps'} = $keymaps;
}

# virtual methods

# raw io methods to be overwritten by child class
sub raw_keyboard_io(@) {

    # parameter: arrayref of the bytes to send one key(-combination)
    #            with all needed keydown/keyup actions
    my $self = shift;
    print STDERR "Error: Not Implemented!\n";
}

sub keycode_down($) {

    # gets key name, returns scancode array
    my $self = shift;
    print STDERR "Error: Not Implemented!\n";
}

sub keycode_up($) {

    # gets key name, returns scancode array
    my $self = shift;
    print STDERR "Error: Not Implemented!\n";
}

# virtual methods end

sub send_key($) {
    my $self  = shift;
    my $key   = shift;
    my @codes = ();
    foreach my $part ( reverse split( "-", $key ) ) {
        unshift( @codes, $self->keycode_down($part) );
        push( @codes, $self->keycode_up($part) );
    }
    my @codes_print = map( sprintf( "0x%02X", $_ ), @codes );

    #print STDOUT "send_key($key) => @codes_print\n";
    $self->raw_keyboard_io( \@codes );
}

1;
# vim: set sw=4 et:
