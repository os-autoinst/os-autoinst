package testapi;

use base Exporter;
use Exporter;
use strict;
use File::Basename qw(basename);
use Time::HiRes qw(sleep gettimeofday);

our @EXPORT = qw($realname $username $password $serialdev %cmd %vars send_key type_string
  assert_screen upload_logs check_screen wait_idle wait_still_screen assert_and_dclick script_run
  script_sudo wait_serial save_screenshot wait_screen_change record_soft_failure
  assert_and_click mouse_hide mouse_set mouse_click mouse_dclick
  type_password get_var check_var set_var become_root x11_start_program ensure_installed
  autoinst_url script_output validate_script_output eject_cd power);

our %cmd;

our $distri;

our $realname = "Bernhard M. Wiedemann";
our $username;
our $password;

our $serialdev;

sub send_key($;$);
sub check_screen($;$);
sub type_string($;$);
sub type_password;

sub init() {
    $serialdev = get_var('SERIALDEV', "ttyS0");
    if ( get_var('OFW') ) {
        $serialdev = "hvc0";
    }

}

sub set_distribution($) {
    ($distri) = @_;
    $distri->init();
}

sub save_screenshot {
    $autotest::current_test->take_screenshot;
}

sub record_soft_failure {
    bmwqemu::fctlog('record_soft_failure');
    $autotest::current_test->{dents}++;
}

sub assert_screen($;$) {
    bmwqemu::fctlog( 'assert_screen', ["mustmatch", $_[0]], ["timeout", $_[1]] );
    return bmwqemu::assert_screen( mustmatch => $_[0], timeout => $_[1] );
}

sub check_screen($;$) {
    bmwqemu::fctlog( 'check_screen', ["mustmatch", $_[0]], ["timeout", $_[1]] );
    return bmwqemu::assert_screen( mustmatch => $_[0], timeout => $_[1], check => 1 );
}

=head2 assert_and_click

assert_and_click($mustmatch,[$button],[$timeout],[$click_time],[$dclick]);

=cut

sub assert_and_click($;$$$$) {
    my $foundneedle = bmwqemu::assert_screen(
        mustmatch => $_[0],
        timeout   => $_[2]
    );
    my $old_mouse_coords = $bmwqemu::backend->get_last_mouse_set();
    bmwqemu::fctlog( 'assert_and_click', ["mustmatch", $_[0]], ["button", $_[1]], ["timeout", $_[2]] );

    my $dclick = $_[4] || 0;

    # foundneedle has to be set, or the assert is buggy :)
    my $lastarea = $foundneedle->{'area'}->[-1];
    my $rx = 1;                                                   # $origx / $img->xres();
    my $ry = 1;                                                   # $origy / $img->yres();
    my $x  = int(( $lastarea->{'x'} + $lastarea->{'w'} / 2 ) * $rx);
    my $y  = int(( $lastarea->{'y'} + $lastarea->{'h'} / 2 ) * $ry);
    bmwqemu::diag("clicking at $x/$y");
    mouse_set( $x, $y );
    if ($dclick) {
        mouse_dclick( $_[1], $_[3] );
    }
    else {
        mouse_click( $_[1], $_[3] );
    }
    # We can't just move the mouse, or we end up in a click-and-drag situation
    sleep 1;
    # move mouse back to where it was before we clicked
    mouse_set( $old_mouse_coords->{'x'}, $old_mouse_coords->{'y'});
}

sub assert_and_dclick($;$$$) {
    assert_and_click($_[0], $_[1], $_[2], $_[3], 1);
}

=head2 wait_idle

wait_idle([$timeout_sec])

Wait until the system becomes idle (as configured by IDLETHESHOLD)

=cut

sub wait_idle(;$) {
    my $timeout = shift || 19;
    bmwqemu::fctlog( 'wait_idle', ["timeout", $timeout] );

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

    bmwqemu::fctlog( 'wait_serial', ["regex", $regexp], ["timeout", $timeout] );
    return bmwqemu::wait_serial($regexp, $timeout, $expect_not_found);
}

=head2 become_root

open a root shell. the implementation is distribution specific, openSUSE calls su -c bash and chdirs to /tmp

=cut

sub become_root() {
    return $distri->become_root;
}

=head2 upload_logs

upload log file to openqa host

=cut

sub upload_logs($) {
    my $file = shift;
    my $host = "10.0.2.2:" . (get_var('QEMUPORT') + 1);

    bmwqemu::fctlog( 'upload_logs', ["file", $file]);
    type_string("curl --form upload=\@$file ");
    my $basename = basename($file);
    type_string("$host/uploadlog/$basename\n");
    wait_idle();
}

sub ensure_installed {
    return $distri->ensure_installed(@_);
}

=head2 wait_still_screen

wait_still_screen([$stilltime_sec [, $timeout_sec [, $similarity_level]]])

Wait until the screen stops changing

=cut

sub wait_still_screen(;$$$) {
    my $stilltime        = shift || 7;
    my $timeout          = shift || 30;
    my $similarity_level = shift || ( get_var('HW') ? 44 : 47 );

    bmwqemu::fctlog( 'wait_still_screen', ["stilltime", $stilltime], ["timeout", $timeout], ["simlvl", $similarity_level] );
    return bmwqemu::wait_still_screen($stilltime, $timeout, $similarity_level);
}

sub clear_console() {
    bmwqemu::fctlog('clear_console');
    send_key "ctrl-c";
    sleep 1;
    send_key "ctrl-c";
    type_string "reset\n";
    sleep 2;
}

sub get_var($;$) {
    my ($var, $default) = @_;
    return $bmwqemu::vars{$var} // $default;
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

sub x11_start_program($;$$) {
    my ($program, $timeout, $options) = @_;
    bmwqemu::fctlog( 'x11_start_program', ["timeout", $timeout], ["options", $options]);
    return $distri->x11_start_program($program, $timeout, $options);
}

=head2 script_run

script_run($program, [$wait_seconds])

Run $program (by assuming the console prompt and typing it).
Wait for idle before  and after.

=cut

sub script_run($;$) {

    my ($name, $wait) = @_;

    bmwqemu::fctlog( 'script_run', ["name", $name], ["wait", $wait]);
    return $distri->script_run($name, $wait);
}

=head2 script_sudo

script_sudo($program, [$wait_seconds])

Run $program. Handle the sudo timeout and send password when appropriate.

$wait_seconds

=cut

sub script_sudo($;$) {
    my ($name, $wait) = @_;

    bmwqemu::fctlog( 'script_sudo', ["name", $name], ["wait", $wait]);
    return $distri->script_sudo($name, $wait);
}

sub power($) {

    # params: (on), off, acpi, reset
    my $action = shift;
    bmwqemu::fctlog( 'power', ["action", $action] );
    $bmwqemu::backend->power({'action' => $action});
}

# eject the cd
sub eject_cd() {
    bmwqemu::fctlog('eject_cd');
    $bmwqemu::backend->eject_cd;
}

# runtime keyboard/mouse io functions end

# runtime information gathering functions

# runtime keyboard/mouse io functions

## keyboard

=head2 send_key

send_key($qemu_key_name[, $wait_idle])

=cut

sub send_key($;$) {
    my $key = shift;
    my $wait = shift || 0;
    bmwqemu::fctlog( 'send_key', ["key", $key] );
    eval { $bmwqemu::backend->send_key($key); };
    bmwqemu::mydie("Error send_key key=$key: $@\n") if ($@);
    wait_idle() if $wait;
}

=head2 type_string

type_string($string, [$max_interval])

send a string of characters, mapping them to appropriate key names as necessary

max_interval (1-250) determines the typing speed, the lower the
max_interval the slower the typing.
=cut

sub type_string($;$) {
    my $string      = shift;
    my $max_interval = shift || 250;
    bmwqemu::fctlog( 'type_string', ["string", "'$string'"], ["max_interval", "'$max_interval'"] );
    $bmwqemu::backend->type_string($string, $max_interval);
}

sub type_password() {
    type_string $password;
}

## keyboard end

## mouse
sub mouse_set($$) {
    my ($mx, $my) = @_;

    bmwqemu::fctlog( 'mouse_set', ["x", $mx], ["y", $my] );
    $bmwqemu::backend->mouse_set( { 'x' => $mx, 'y' => $my } );
}

sub mouse_click(;$$) {
    my $button = shift || 'left';
    my $time   = shift || 0.15;
    bmwqemu::fctlog( 'mouse_click', ["button", $button], ["cursor_down", $time] );
    $bmwqemu::backend->mouse_button( $button, 1 );
    sleep $time;
    $bmwqemu::backend->mouse_button( $button, 0 );
}

sub mouse_dclick(;$$) {
    my $button = shift || 'left';
    my $time   = shift || 0.10;
    bmwqemu::fctlog( 'mouse_dclick', ["button", $button], ["cursor_down",  $time] );
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
    bmwqemu::fctlog( 'mouse_hide', ["border_offset", $border_offset] );
    $bmwqemu::backend->mouse_hide($border_offset);
}
## mouse end

=head2 autoinst_url

returns the base URL to contact the local os-autoinst service

=cut

sub autoinst_url() {
    # move to backend?
    return "http://10.0.2.2:" . (get_var("QEMUPORT")+1);
}

=head2 script_output

script_output($script, [$wait])

fetches the script through HTTP into the VM and execs it with bash -xe and directs
stdout (*not* stderr!) to the serial console and returns the output *if* the script
exists with 0. Otherwise the test is set to failed.

The default timeout for the script is 10 seconds. If you need more, pass a 2nd parameter

=cut

sub _random_string() {
    my $string;
    my @chars = ('a'..'z', 'A'..'Z');
    $string .= $chars[rand @chars] for 1..4;
    return $string;
}

sub script_output($;$) {
    my $wait;
    ($commands::current_test_script, $wait) = @_;
    $commands::current_test_script .= "\necho SCRIPT_FINISHED\n";
    $wait ||= 10;

    my $suffix = _random_string;
    type_string "curl -f -v " . autoinst_url . "/current_script > /tmp/script$suffix.sh && echo \"curl-$?\" > /dev/$serialdev\n";
    wait_serial('curl-0', 2) || die "script couldn't be downloaded";
    send_key "ctrl-l";

    type_string "/bin/bash -ex /tmp/script$suffix.sh > /dev/$serialdev\n";
    my $output = wait_serial('SCRIPT_FINISHED', $wait) or die "script failed";

    # strip the internal exit catcher
    $output =~ s,SCRIPT_FINISHED,,;

    # trim whitespaces
    $output =~ s/^\s+|\s+$//g;

    return $output;
}

=head2 validate_script_output

validate_script_output($script, $code, [$wait])

wrapper around script_output, that runs a callback on the output. Use it as

validate_script_output "cat /etc/hosts", sub { m/127.*localhost/ }

=cut

sub validate_script_output($&;$) {
    my ($script, $code, $wait) = @_;
    $wait ||= 10;

    my $output = script_output($script, $wait);
    return unless $code;
    my $res = 'ok';

    # set $_ so the callbacks can be simpler code
    $_ = $output;
    if (!$code->()) {
        $res = 'fail';
        bmwqemu::diag("output does not pass the code block:\n$output");
    }
    # abusing the function
    $autotest::current_test->record_serialresult($output, $res);
    if ($res eq 'fail') {
        die "output not validating";
    }
}

=head2 wait_screen_change

wait_screen_change($code)

wrapper around code that is supposed to change the screen. This is basically the
opposite to wait_still_screen. Make sure to put the commands to change the screen
within the block to avoid races between the action and the screen change

wait_screen_change {
   send_key 'esc';
}

=cut

sub wait_screen_change(&@) {
    my ($callback) = @_;

    bmwqemu::fctlog('wait_screen_change');

    # get the initial screen
    my $refimg = bmwqemu::getcurrentscreenshot();
    $callback->() if $callback;

    my $starttime = time;
    my $timeout = 10;
    my $similarity_level = 50;

    while ( time - $starttime < $timeout ) {
        my $img = bmwqemu::getcurrentscreenshot();
        my $sim = $img->similarity($refimg);
        print "waiting for screen change: " . (time - $starttime) . " $sim\n";
        if ( $sim < $similarity_level ) {
            bmwqemu::fctres( 'wait_screen_change', "screen change seen at " . (time - $starttime) );
            return 1;
        }
        sleep(0.5);
    }
    save_screenshot;
    bmwqemu::fctres( 'wait_screen_change', "timed out" );
    return 0;
}

## helpers end

1;

# vim: set sw=4 et:
