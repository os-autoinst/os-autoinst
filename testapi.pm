package testapi;

use base Exporter;
use Exporter;

use File::Basename qw(basename);

our ( @EXPORT, @EXPORT_OK, %EXPORT_TAGS );

@EXPORT = qw($realname $username $password $serialdev %cmd %vars send_key type_string assert_screen
  upload_logs check_screen wait_idle wait_still_screen assert_and_dclick script_run
  script_sudo wait_serial save_screenshot backend_send assert_and_click mouse_hide mouse_set mouse_click mouse_dclick
  type_password wait_encrypt_prompt get_var check_var set_var become_root x11_start_program ensure_installed);

our %cmd;

our %charmap;

our $realname = "Bernhard M. Wiedemann";
our $username;
our $password;

our $serialdev;

sub send_key($;$);
sub check_screen($;$);
sub type_string($;$);
sub type_password;

sub init_charmap() {
    ## charmap (like L => shift+l)
    %charmap = (
        ","  => "comma",
        "."  => "dot",
        "/"  => "slash",
        "="  => "equal",
        "-"  => "minus",
        "*"  => "asterisk",
        "["  => "bracket_left",
        "]"  => "bracket_right",
        "{"  => "shift-bracket_left",
        "}"  => "shift-bracket_right",
        "\\" => "backslash",
        "|"  => "shift-backslash",
        ";"  => "semicolon",
        ":"  => "shift-semicolon",
        "'"  => "apostrophe",
        '"'  => "shift-apostrophe",
        "`"  => "grave_accent",
        "~"  => "shift-grave_accent",
        "<"  => "shift-comma",
        ">"  => "shift-dot",
        "+"  => "shift-equal",
        "_"  => "shift-minus",
        '?'  => "shift-slash",
        "\t" => "tab",
        "\n" => "ret",
        " "  => "spc",
        "\b" => "backspace",
        "\e" => "esc"
    );
    for my $c ( "A" .. "Z" ) {
        $charmap{$c} = "shift-\L$c";
    }
    {
        my $n = 0;
        for my $c ( ')', '!', '@', '#', '$', '%', '^', '&', '*', '(' ) {
            $charmap{$c} = "shift-" . ( $n++ );
        }
    }
    ## charmap end
}

sub init() {
    init_charmap();

    $serialdev = "ttyS0";
    if ( get_var('OFW') ) {
        $serialdev = "hvc0";
    }

}


sub assert_screen($;$) {
    return bmwqemu::assert_screen( mustmatch => $_[0], timeout => $_[1] );
}

sub check_screen($;$) {
    return bmwqemu::assert_screen( mustmatch => $_[0], timeout => $_[1], check => 1 );
}

sub assert_and_click($;$$$$) {
    my $foundneedle = bmwqemu::assert_screen(
        mustmatch => $_[0],
        timeout   => $_[2]
    );
    my $dclick = $_[4] || 0;

    # foundneedle has to be set, or the assert is buggy :)
    my $lastarea = $foundneedle->{'area'}->[-1];
    my $rx = 1;                                                   # $origx / $img->xres();
    my $ry = 1;                                                   # $origy / $img->yres();
    my $x  = int(( $lastarea->{'x'} + $lastarea->{'w'} / 2 ) * $rx);
    my $y  = int(( $lastarea->{'y'} + $lastarea->{'h'} / 2 ) * $ry);
    diag("clicking at $x/$y");
    mouse_set( $x, $y );
    if ($dclick) {
        mouse_dclick( $_[1], $_[3] );
    }
    else {
        mouse_click( $_[1], $_[3] );
    }
}

sub assert_and_dclick($;$$$) {
    assert_and_click($_[0], $_[1], $_[2], $_[3], 1);
}

=head2 wait_idle

wait_idle([$timeout_sec])

Wait until the system becomes idle (as configured by IDLETHESHOLD in env.sh)

=cut

sub wait_idle(;$) {
    my $timeout = shift || 19;
    bmwqemu::wait_idle($timeout);
}

=head2 wait_serial

wait_serial($regex [[, $timeout_sec], $expect_not_found])

Wait for a message to appear on serial output.
You could have sent it there earlier with

C<script_run("echo Hello World E<gt> /dev/$serialdev");>

=cut

sub wait_serial($;$$) {

    # wait for a message to appear on serial output
    my $regexp = shift;
    my $timeout = shift || 90;    # seconds
    my $expect_not_found = shift || 0;    # expected can not found the term in serial output

    bmwqemu::wait_serial($regexp, $timeout, $expect_not_found);
}

sub become_root() {
    script_sudo( "bash", 0 );    # become root
    script_run("echo 'imroot' > /dev/$serialdev");
    wait_serial( "imroot", 5 ) || die "Root prompt not there";
    script_run("cd /tmp");
}

=head2 upload_logs

upload log file to openqa host

=cut

sub upload_logs($) {
    my $file = shift;
    type_string("curl --form testname=$bmwqemu::testedversion");
    my $host = get_var('OPENQA_HOSTNAME');
    if ($host) {
        type_string(" --resolve $host:80:10.0.2.2");
    }
    else {
        $host = '10.0.2.2';
    }
    type_string(" --form upload=\@$file ");
    if ( defined get_var('TEST_ID') ) {
        my $basename = basename($file);
        type_string("$host/tests/" . get_var('TEST_ID') . "/uploadlog/$basename");
    }
    else {
        type_string("$host/cgi-bin/uploadlog");
    }
    send_key 'ret';
}

sub ensure_installed {
    return $bmwqemu::current_test->ensure_installed(@_);
}

=head2 wait_still_screen

wait_still_screen([$stilltime_sec [, $timeout_sec [, $similarity_level]]])

Wait until the screen stops changing

=cut

sub wait_still_screen(;$$$) {
    my $stilltime        = shift || 7;
    my $timeout          = shift || 30;
    my $similarity_level = shift || ( get_var('HW') ? 44 : 47 );

    return bmwqemu::wait_still_screen($stilltime, $timeout, $similarity_level);
}

sub clear_console() {
    send_key "ctrl-c";
    sleep 1;
    send_key "ctrl-c";
    type_string "reset\n";
    sleep 2;
}

sub get_var($;$) {
    my ($var, $default) = @_;
    return $bmwqemu::vars{$var} || $default;
}

sub set_var($$) {
    my ($var, $val) = @_;
    $bmwqemu::vars{$var} = $val;
}

sub check_var($$) {
    my ($var, $val) = @_;
    return 1 if ( defined $bmwqemu::vars{$var} && $bmwqemu::vars{$var} eq $val );
    return 0;
}

## helpers
sub wait_encrypt_prompt() {
    if ( $bmwqemu::vars{ENCRYPT} ) {
        assert_screen("encrypted-disk-password-prompt");
        type_password();    # enter PW at boot
        send_key "ret";
    }
}

sub x11_start_program($;$$) {
    my ($program, $timeout, $options) = @_;
    $timeout ||= 6;
    $options ||= {};
    return $bmwqemu::current_test->x11_start_program($program, $timeout, $options);
}

=head2 script_run

script_run($program, [$wait_seconds])

Run $program (by assuming the console prompt and typing it).
Wait for idle before  and after.

=cut

sub script_run($;$) {

    # start console application
    my $name = shift;
    my $wait = shift || 9;
    wait_idle();
    type_string "$name\n";
    wait_idle($wait);
    sleep 3;
}

=head2 script_sudo

script_sudo($program, [$wait_seconds])

Run $program. Handle the sudo timeout and send password when appropriate.

$wait_seconds
=cut

sub script_sudo($;$) {
    my $prog = shift;
    my $wait = shift || 2;
    type_string "sudo $prog\n";
    if ( check_screen "sudo-passwordprompt", 3 ) {
        type_password;
        send_key "ret";
    }
    wait_idle($wait);
}

sub power($) {

    # params: (on), off, acpi, reset
    my $action = shift;
    fctlog( 'power', "action=$action" );
    $bmwqemu::backend->power($action);
}

# runtime keyboard/mouse io functions end

# runtime information gathering functions

sub save_screenshot {
    $bmwqemu::current_test->take_screenshot;
}

sub timeout_screenshot() {
    my $n = ++$timeoutcounter;
    $bmwqemu::current_test->take_screenshot( sprintf( "timeout-%02i", $n ) );
}

sub _backend_send_nolog($) {

    # should not be used if possible
    if ($bmwqemu::backend) {
        $bmwqemu::backend->send(@_);
    }
    else {
        warn "no backend";
    }
}

sub backend_send($) {

    # should not be used if possible
    fctlog( 'backend_send', join( ',', @_ ) );
    &_backend_send_nolog;
}

# backend management end

# runtime keyboard/mouse io functions

## keyboard

=head2 send_key

send_key($qemu_key_name[, $wait_idle])

=cut

sub send_key($;$) {
    my $key = shift;
    my $wait = shift || 0;
    bmwqemu::fctlog( 'send_key', "key=$key" );
    eval { $bmwqemu::backend->send_key($key); };
    bmwqemu::mydie("Error send_key key=$key: $@\n") if ($@);
    wait_idle() if $wait;
}

=head2 type_string

type_string($string)

send a string of characters, mapping them to appropriate key names as necessary

=cut

sub type_string($;$) {
    my $string      = shift;
    my $maxinterval = shift || 250;
    bmwqemu::fctlog( 'type_string', "string='$string'" );
    if ($bmwqemu::backend->can('type_string')) {
        $bmwqemu::backend->type_string($string, $maxinterval);
    }
    else {
        my $typedchars  = 0;
        my @letters = split( "", $string );
        while (@letters) {
            my $letter = shift @letters;
            if ( $charmap{$letter} ) { $letter = $charmap{$letter} }
            send_key $letter, 0;
            if ( $typedchars++ >= $maxinterval ) {
                wait_still_screen(1.6);
                $typedchars = 0;
            }
        }
        wait_still_screen(1.6) if ( $typedchars > 0 );
    }
}

sub type_password() {
    type_string $password;
}

## keyboard end

## mouse
sub mouse_set($$) {
    my $mx = shift;
    my $my = shift;
    bmwqemu::fctlog( 'mouse_set', "x=$mx", "y=$my" );
    $bmwqemu::backend->mouse_set( $mx, $my );
}

sub mouse_click(;$$) {
    my $button = shift || 'left';
    my $time   = shift || 0.15;
    bmwqemu::fctlog( 'mouse_click', "button=$button", "cursor_down=$time" );
    $bmwqemu::backend->mouse_button( $button, 1 );
    sleep $time;
    $bmwqemu::backend->mouse_button( $button, 0 );
}

sub mouse_dclick(;$$) {
    my $button = shift || 'left';
    my $time   = shift || 0.10;
    bmwqemu::fctlog( 'mouse_dclick', "button=$button", "cursor_down=$time" );
    $bmwqemu::backend->mouse_button( $button, 1 );
    sleep $time;
    $bmwqemu::backend->mouse_button( $button, 0 );
    sleep $time;
    $bmwqemu::backend->mouse_button( $button, 1 );
    sleep $time;
    $bmwqemu::backend->mouse_button( $button, 0 );
}

sub mouse_hide(;$) {
    my $border_offset = shift || 0;
    bmwqemu::fctlog( 'mouse_hide', "border_offset=$border_offset" );
    $bmwqemu::backend->mouse_hide($border_offset);
}
## mouse end

## helpers end

1;

# vim: set sw=4 et:
