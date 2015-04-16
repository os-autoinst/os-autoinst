#!/usr/bin/perl -w
use strict;
# usage: $0 daemon --listen http://:::3000

use Mojolicious::Lite;
use MojoX::JSON::RPC::Service;
use Fcntl;
use Time::HiRes "sleep";

my $hidfile = "/dev/hidg0";

my $modifier = {
    'ctrl'    => 0x01,
    'shift'   => 0x02,
    'alt'     => 0x04,
    'meta'    => 0x08,
    'r_ctrl'  => 0x10,
    'r_shift' => 0x20,
    'r_alt'   => 0x40,
    'r_meta'  => 0x80,
};

my $keymap_usb = {
    'win'         => 0xe3,
    'caps_lock'   => 0x39,
    'print'       => 0x46,
    'scroll_lock' => 0x47,

    'pause'  => 0x48,
    'end'    => 0x4d,
    'delete' => 0x4c,
    'home'   => 0x4a,
    'insert' => 0x49,

    'pgup' => 0x4b,
    'pgdn' => 0x4e,

    'left'  => 0x50,
    'right' => 0x4f,
    'up'    => 0x52,
    'down'  => 0x51,

    'num_lock'    => 0x53,
    'kp_divide'   => 0x54,
    'kp_multiply' => 0x55,
    'kp_subtract' => 0x56,
    'kp_add'      => 0x57,
    'kp_enter'    => 0x58,
    'kp_0'        => 0x62,
    'kp_decimal'  => 0x63,
    'dunno1'      => 0x64,
    'application' => 0x65,
    'power'       => 0x66,
    'kp_equals'   => 0x67,

    '0'         => 0x27,
    'ret'       => 0x28,
    'esc'       => 0x29,
    'backspace' => 0x2a,
    'tab'       => 0x2b,
    'spc'       => 0x2c,
    'minus'     => 0x2d,
    '='         => 0x2e,
    '['         => 0x2f,
    ']'         => 0x30,
    '\\'        => 0x31,
    '#'         => 0x32,
    ';'         => 0x33,
    '\''        => 0x34,
    '`'         => 0x35,
    ','         => 0x36,
    '.'         => 0x37,
    '/'         => 0x38,
};

sub init_usb_keymap {
    my $keymap = $keymap_usb;
    for my $key ("a" .. "z") {
        my $code = 0x4 + ord($key) - ord('a');
        $keymap->{$key} = $code;
        $keymap->{uc($key)} = $code;
    }
    for my $key ("1" .. "9") {
        $keymap->{$key} = 0x1e + ord($key) - ord('1');
        $keymap->{"kp_$key"} = 0x59 + ord($key) - ord('1');
    }
    for my $key (1 .. 12) {
        $keymap->{"f$key"} = 0x3a + $key - 1,;
    }
    return $keymap;
}
our $keymap = init_usb_keymap();

sub key_code($) {
    my $key   = shift;
    my $mod   = 0;
    my @codes = ();
    foreach my $part (split("-", $key)) {
        if (my $m = $modifier->{$part}) {
            $mod |= $m;
        }
        elsif ((my $code = $keymap->{$part})) {
            if (@codes >= 6) { die "too many keys at a time in $key" }
            push(@codes, $code);
        }
        else {
            die "invalid key $part in $key";
        }
    }
    unshift(@codes, $mod, 0);
    return @codes;
}

sub send_key($) {
    my @codes = key_code($_[0]);
    print "@codes\n";    # debug
    my $data = pack("C*", @codes);
    open(HID, "+<", $hidfile) or die "error opening $hidfile: $!";
    syswrite(HID, $data);    # key-press
    foreach (@codes) { $_ = 0 }
    $data = pack("C*", @codes);
    syswrite(HID, $data);    # key-release
    close HID;
}

our $charmap = {
    # minus is special as it splits key combinations
    "-" => "minus",
    # first line of US layout
    "~"  => "shift-`",
    "!"  => "shift-1",
    "@"  => "shift-2",
    "#"  => "shift-3",
    "\$" => "shift-4",
    "%"  => "shift-5",
    "^"  => "shift-6",
    "&"  => "shift-7",
    "*"  => "shift-8",
    "("  => "shift-9",
    ")"  => "shift-0",
    "_"  => "shift-minus",
    "+"  => "shift-=",

    # second line
    "{" => "shift-[",
    "}" => "shift-]",
    "|" => "shift-\\",

    # third line
    ":" => "shift-;",
    '"' => "shift-'",

    # fourth line
    "<" => "shift-,",
    ">" => "shift-.",
    '?' => "shift-/",

    " "  => "spc",
    "\t" => "tab",
    "\n" => "ret",
    "\b" => "backspace",

    "\e" => "esc"
};
## charmap end

sub map_letter($) {
    my ($letter) = @_;
    return $charmap->{$letter} if $charmap->{$letter};
    return $letter;
}

sub type_string($) {
    my ($string) = @_;
    for my $letter (split("", $string)) {
        send_key map_letter($letter);
        sleep 0.02;
    }
}

sub change_cd($) {
    my $filename = shift;
    my $b        = "/sys/kernel/config/usb_gadget/usbarmory";
    my $c        = "$b/configs/c.1/mass_storage.usb0";
    my $f        = "$b/functions/mass_storage.usb0";
    unlink($c);
    open(my $fh, ">", "$f/lun.0/file") or die $!;
    print $fh $filename;
    close $fh;
    symlink($f, $c) or die $!;
    system("ls /sys/class/udc > $b/UDC");
}

sub read_serial() {
    my $dev = "/dev/ttyGS0";
    open(my $fh, "<", $dev)    # FIXME blocking is not good
      or die "Can't open $dev: $!";
    my $data = <$fh>;
    #my $nr = read($fh, $data, 1);
    close $fh;
    return $data;
    return undef;
}

sub init_usb_gadget() {
    return if (-e "/sys/kernel/config/usb_gadget/usbarmory");
    system("/usr/local/sbin/usb-gadget-init.sh");
}

#send_key("shift-a");
#while(<>) { chomp; send_key($_); }

my $svc = MojoX::JSON::RPC::Service->new;
$svc->register('init_usb_gadget', \&init_usb_gadget);
$svc->register('send_key',        \&send_key);
$svc->register('change_cd',       \&change_cd);
$svc->register('read_serial',     \&read_serial);

plugin 'json_rpc_dispatcher' => {services => {'/jsonrpc' => $svc}};

app->start;
