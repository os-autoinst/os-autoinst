# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2018 SUSE LLC
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

package testapi;

use base Exporter;
use Carp;
use Exporter;
use 5.018;
use warnings;
use File::Basename qw(basename dirname);
use File::Path 'make_path';
use Time::HiRes qw(sleep gettimeofday tv_interval);
use autotest 'query_isotovideo';
use Mojo::DOM;
require IPC::System::Simple;
use autodie ':all';
use OpenQA::Exceptions;
use Digest::MD5 'md5_base64';
use Carp qw(cluck croak);
use MIME::Base64 'decode_base64';
use Scalar::Util 'looks_like_number';

require bmwqemu;
use constant OPENQA_LIBPATH => '/usr/share/openqa/lib';

our @EXPORT = qw($realname $username $password $serialdev %cmd %vars

  get_var get_required_var check_var set_var get_var_array check_var_array autoinst_url

  send_key send_key_until_needlematch type_string type_password
  hold_key release_key

  assert_screen check_screen assert_and_dclick save_screenshot
  assert_and_click mouse_hide mouse_set mouse_click
  mouse_dclick mouse_tclick match_has_tag

  assert_script_run script_run assert_script_sudo script_sudo
  script_output validate_script_output

  start_audiocapture assert_recorded_sound check_recorded_sound

  select_console console reset_consoles

  upload_asset data_url assert_shutdown parse_junit_log parse_extra_log upload_logs

  wait_idle wait_screen_change assert_screen_change wait_still_screen wait_serial
  record_soft_failure record_info
  become_root x11_start_program ensure_installed eject_cd power

  save_memory_dump save_storage_drives freeze_vm resume_vm

  diag hashed_string

  save_tmp_file get_test_data
);
our @EXPORT_OK = qw(is_serial_terminal);

our %cmd;

our $distri;

our $realname = "Bernhard M. Wiedemann";
our $username;
our $password;

our $serialdev;
our $selected_console;

our $last_matched_needle;

sub send_key;
sub check_screen;
sub type_string;
sub type_password;


=head1 introduction

=for stopwords os autoinst isotovideo openQA

This test API module provides methods exposed by the os-autoinst backend to be
used within tests.

Many methods define a timeout parameter which can be scaled by setting the
C<TIMEOUT_SCALE> variable in the test settings which are read by the isotovideo
process. The scale parameter can be used based on performance of workers to
prevent false positive timeouts based on differing worker performance.

os-autoinst is used in the openQA project.
+For more information on how to use openQA, please visit http://open.qa/documentation

=cut

=head1 internal

=for stopwords xen hvc0 xvc0 ipmi ttyS

=head2 init

Used for internal initialization, do not call from tests.

=cut

sub init {
    if (get_var('SERIALDEV')) {
        $serialdev = get_var('SERIALDEV');
    }
    elsif (get_var('OFW') || check_var('BACKEND', 's390x')) {
        $serialdev = "hvc0";
    }
    else {
        $serialdev = 'ttyS0';
    }
    $serialdev = 'ttyS1' if check_var('BACKEND', 'ipmi');
    return;
}

=for stopwords ProhibitSubroutinePrototypes

=head2 set_distribution

    set_distribution($distri);

Set distribution object.

You can use distribution object to implement distribution specific helpers.

=cut

## no critic (ProhibitSubroutinePrototypes)
sub set_distribution {
    ($distri) = @_;
    return $distri->init();
}

=for stopwords SUT

=head1 video output handling

=head2 save_screenshot

  save_screenshot;

Saves screenshot of current SUT screen.

=cut

sub save_screenshot {
    return $autotest::current_test->take_screenshot;
}

=head2 record_soft_failure

  record_soft_failure([$reason]);

Record a soft failure on the current test modules result. The result will
still be counted as a success. Use this to mark where workarounds are applied.
Takes an optional C<$reason> string which is recorded in the log file.

=cut

sub record_soft_failure {
    my ($reason) = @_;
    bmwqemu::log_call(reason => $reason);

    $autotest::current_test->record_soft_failure_result($reason);
    $autotest::current_test->{dents}++;
}

sub _is_valid_result {
    my ($result) = @_;
    return $result =~ /^(ok|fail|softfail)$/;
}

=head2 record_info

=for stopwords softfail

    record_info($title, $output [, result => $result] [, resultname => $resultname]);

Example:

  record_info('workaround', "we know what we are doing");

Record a generic step result on the current test modules. This is meant for
informational purposes to be interpreted by a displaying system. For example
openQA can show a info box as part of the job results details. Use this
instead of C<record_soft_failure> for example when you do not want to mark the
job as a softfail. The optional value C<$result> can be 'ok' (default),
'fail', 'softfail'. C<$resultname> can be specified for the additional name
tag on the result file.

=cut

sub record_info {
    my ($title, $output, %nargs) = @_;
    $nargs{result} //= 'ok';
    die 'unsupported $result \'' . $nargs{result} . '\'' unless _is_valid_result($nargs{result});
    bmwqemu::log_call(title => $title, output => $output, %nargs);
    $autotest::current_test->record_resultfile($title, $output, %nargs);
}

sub _handle_found_needle {
    my ($foundneedle, $rsp, $tags) = @_;
    # convert the needle back to an object
    $foundneedle->{needle} = needle->new($foundneedle->{needle});
    my $img   = tinycv::from_ppm(decode_base64($rsp->{image}));
    my $frame = $rsp->{frame};
    $autotest::current_test->record_screenmatch($img, $foundneedle, $tags, $rsp->{candidates}, $frame);
    my $lastarea = $foundneedle->{area}->[-1];
    bmwqemu::fctres(
        sprintf("found %s, similarity %.2f @ %d/%d", $foundneedle->{needle}->{name}, $lastarea->{similarity}, $lastarea->{x} // 0, $lastarea->{y} // 0));
    $last_matched_needle = $foundneedle;
    return $foundneedle;
}


sub _check_backend_response {
    my ($rsp, $check, $timeout, $mustmatch) = @_;

    my $tags = $rsp->{tags};

    if (my $foundneedle = $rsp->{found}) {
        return _handle_found_needle($foundneedle, $rsp, $tags);
    }
    elsif ($rsp->{timeout}) {
        bmwqemu::fctres("match=" . join(',', @$tags) . " timed out after $timeout");
        my $failed_screens = $rsp->{failed_screens};
        my $final_mismatch = $failed_screens->[-1];
        if ($check) {
            # only care for the last one
            $failed_screens = [$final_mismatch];
        }
        for my $l (@$failed_screens) {
            my $img = tinycv::from_ppm(decode_base64($l->{image}));
            my $result = $check ? 'unk' : 'fail';
            $result = 'unk' if ($l != $final_mismatch);
            if ($rsp->{saveresult}) {
                $autotest::current_test->record_screenfail(
                    img     => $img,
                    needles => $l->{candidates},
                    tags    => $tags,
                    result  => $result,
                    frame   => $l->{frame},
                );
            }
            else {
                $autotest::current_test->record_screenfail(
                    img     => $img,
                    needles => $l->{candidates},
                    tags    => $tags,
                    result  => $result,
                    overall => $check ? undef : 'fail',
                    frame   => $l->{frame},
                );
            }
        }
        # Handle case where a stall was detected: fail if this is an
        # assert_screen, warn if it's a check_screen
        if ($rsp->{stall}) {
            if (!$check) {
                record_info('Stall detected', 'Stall was detected during assert_screen fail', result => 'fail');
            }
            else {
                bmwqemu::fctwarn("stall detected during check_screen failure!");
            }
        }
        if (!$check && !$rsp->{saveresult}) {
            # Must match can be only scalar or array ref.
            my $needletags = $mustmatch;
            if (ref($mustmatch) eq 'ARRAY') {
                $needletags = join(', ', @$mustmatch);
            }
            OpenQA::Exception::FailedNeedle->throw(
                error => "no candidate needle with tag(s) '$needletags' matched",
                tags  => $mustmatch
            );
        }
        if ($rsp->{saveresult}) {
            $autotest::current_test->save_test_result();
            # now back into waiting for the backend
            $rsp = myjsonrpc::read_json($autotest::isotovideo);
            return unless $rsp;
            $rsp = $rsp->{ret};
            $rsp->{tags} = $tags;
            return _check_backend_response($rsp, $check, $timeout, $mustmatch);
        }
    }
    else {
        die "unexpected response " . bmwqemu::pp($rsp);
    }
    return;
}

sub _check_or_assert {
    my ($mustmatch, $check, %args) = @_;
    $args{timeout} = bmwqemu::scale_timeout($args{timeout});

    die "current_test undefined" unless $autotest::current_test;

    my $rsp = query_isotovideo('check_screen', {mustmatch => $mustmatch, check => $check, timeout => $args{timeout}, no_wait => $args{no_wait}});
    # separate function because it needs to call itself
    return _check_backend_response($rsp, $check, $args{timeout}, $mustmatch, $args{no_wait});
}

=head2 assert_screen

  assert_screen($mustmatch [, [$timeout] | [timeout => $timeout]] [, no_wait => $no_wait]);

Wait for needle with tag C<$mustmatch> to appear on SUT screen. C<$mustmatch>
can be string or C<ARRAYREF> of string (C<['tag1', 'tag2']>). The maximum
waiting time is defined by C<$timeout>. It is recommended to use a value lower
than the default timeout only when explicitly needed. C<assert_screen> is not
very suitable for checking performance expectations. Under the normal
circumstance of the screen being shown this does not imply a longer waiting
time as the method returns as soon as a successful needle match occurred.

Specify C<$no_wait> to run the screen check as fast as possible that is
possibly more than once per second which is default. Select this to check a
screen which can change in a range faster than 1-2 seconds not to miss the
screen to check for.

Returns matched needle or throws C<NeedleFailed> exception if $timeout timeout
is hit. Default timeout is 30s.

=cut

sub assert_screen {
    my ($mustmatch) = shift;
    my $timeout;
    $timeout = shift if (@_ % 2);
    my %args = (timeout => $timeout // $bmwqemu::default_timeout, @_);
    bmwqemu::log_call(mustmatch => $mustmatch, %args);
    return _check_or_assert($mustmatch, 0, %args);
}

=head2 check_screen

  check_screen($mustmatch [, [$timeout] | [timeout => $timeout]] [, no_wait => $no_wait]);

Similar to C<assert_screen> but does not throw exceptions. Use this for optional matches.
Check C<assert_screen> for parameters.

Unlike C<assert_screen> it is recommended to use the lowest possible timeout
to prevent needless waiting time in case no match is expected behaviour. In
general a value of 0s for the timeout should suffice, that is only checking
once with no waiting time. In most cases a check_screen with a higher timeout
can be replaced by C<assert_screen> with multiple tags using an C<ARRAYREF> in
combination with C<match_has_tag> or another synchronization call in before,
for example C<wait_screen_change> or C<wait_still_screen>.

Returns matched needle or C<undef> if timeout is hit. Default timeout is 30s.

=cut

sub check_screen {
    my ($mustmatch) = shift;
    my $timeout;
    $timeout = shift if (@_ % 2);
    my %args = (timeout => $timeout // $bmwqemu::default_timeout, @_);
    bmwqemu::log_call(mustmatch => $mustmatch, %args);
    return _check_or_assert($mustmatch, 1, %args);
}

=head2 match_has_tag

  match_has_tag($tag);

Returns true if last matched needle has C<$tag> else return C<undef>.

=cut

sub match_has_tag {
    my ($tag) = @_;
    if ($last_matched_needle) {
        return $last_matched_needle->{needle}->has_tag($tag);
    }
    return;
}

=head2 assert_and_click

  assert_and_click($mustmatch, [$button], [$timeout], [$click_time], [$dclick]);

Wait for needle with C<$mustmatch> tag to appear on SUT screen. Then click
C<$button> in the middle of the last match region as defined in the needle
JSON file. If C<$dclick> is set, do double click instead.  C<$mustmatch> can
be string or C<ARRAYREF> of strings (C<['tag1', 'tag2']>).  C<$button> is by
default C<'left'>. C<'left'> and C<'right'> is supported.

Throws C<NeedleFailed> exception if C<$timeout> timeout is hit. Default timeout is 30s.

=cut

sub assert_and_click {
    my ($mustmatch, $button, $timeout, $clicktime, $dclick) = @_;
    $timeout //= $bmwqemu::default_timeout;

    $dclick //= 0;

    $last_matched_needle = assert_screen($mustmatch, $timeout);
    my $old_mouse_coords = query_isotovideo('backend_get_last_mouse_set');
    bmwqemu::log_call(mustmatch => $mustmatch, button => $button, timeout => $timeout);

    # last_matched_needle has to be set, or the assert is buggy :)
    my $lastarea = $last_matched_needle->{area}->[-1];
    my $rx       = 1;                                                  # $origx / $img->xres();
    my $ry       = 1;                                                  # $origy / $img->yres();
    my $x        = int(($lastarea->{x} + $lastarea->{w} / 2) * $rx);
    my $y        = int(($lastarea->{y} + $lastarea->{h} / 2) * $ry);
    bmwqemu::diag("clicking at $x/$y");
    mouse_set($x, $y);
    if ($dclick) {
        mouse_dclick($button, $clicktime);
    }
    else {
        mouse_click($button, $clicktime);
    }
    # We can't just move the mouse, or we end up in a click-and-drag situation
    sleep 1;
    # move mouse back to where it was before we clicked, or to the 'hidden'
    # position if it had never been positioned
    if ($old_mouse_coords->{x} > -1 && $old_mouse_coords->{y} > -1) {
        return mouse_set($old_mouse_coords->{x}, $old_mouse_coords->{y});
    }
    else {
        return mouse_hide();
    }
}

=head2 assert_and_dclick

  assert_and_dclick($mustmatch, $button, [$timeout], [$click_time]);

Alias for C<assert_and_click> with C<$dclick> set.

=cut

sub assert_and_dclick {
    my ($mustmatch, $button, $timeout, $clicktime) = @_;
    return assert_and_click($mustmatch, $button, $timeout, $clicktime, 1);
}

=head2 wait_screen_change

  wait_screen_change(CODEREF [,$timeout [, similarity_level => 50]]);

Wrapper around code that is supposed to change the screen.
This is the opposite to C<wait_still_screen>. Make sure to put the commands to change the screen
within the block to avoid races between the action and the screen change.

Example:

  wait_screen_change {
     send_key 'esc';
  };

Notice: If you use the second parameter, you could get the following warning

  Useless use of private variable in void context

To avoid it, use parentheses for the function call and the reserved word 'sub' for the callback
subroutine block.

  wait_screen_change(sub {
    send_key 'esc';
  }, 15);

Returns true if screen changed or false on timeout. Default timeout is 10s. Default
similarity_level is 50.

=cut

sub wait_screen_change(&@) {
    my ($callback, $timeout, %args) = @_;
    $timeout ||= 10;
    $args{similarity_level} //= 50;

    bmwqemu::log_call(timeout => $timeout);

    # get the initial screen
    query_isotovideo('backend_set_reference_screenshot');
    $callback->() if $callback;

    my $starttime = time;

    while (time - $starttime < $timeout) {
        my $sim = query_isotovideo('backend_similiarity_to_reference')->{sim};
        bmwqemu::diag("waiting for screen change: " . (time - $starttime) . " $sim");
        if ($sim < $args{similarity_level}) {
            bmwqemu::fctres("screen change seen at " . (time - $starttime));
            return 1;
        }
        sleep(0.5);
    }
    save_screenshot;
    bmwqemu::fctres("timed out");
    return 0;
}

=head2 assert_screen_change

  assert_screen_change(CODEREF [,$timeout]);

Run C<CODEREF> with C<wait_screen_change> but C<die> if screen did not change
within timeout. Look into C<wait_screen_change> for details.

Example:

  assert_screen_change { send_key 'alt-f4' };

=cut

sub assert_screen_change(&@) {
    ::wait_screen_change(@_) or die 'assert_screen_change failed to detect a screen change';
}


=head2 wait_still_screen

=for stopwords stilltime

  wait_still_screen([$stilltime | [stilltime => $stilltime]] [, $timeout] | [timeout => $timeout]] [, similarity_level => $similarity_level] [, no_wait => $no_wait]);

Wait until the screen stops changing.

See C<assert_screen> for C<$no_wait>.

Returns true if screen is not changed for given C<$stilltime> (in seconds) or undef on timeout.
Default timeout is 30s, default stilltime is 7s.

=cut

sub wait_still_screen {
    my $stilltime = looks_like_number($_[0]) ? shift : 7;
    my $timeout = (@_ % 2) ? shift : $bmwqemu::default_timeout;
    my %args = (stilltime => $stilltime, timeout => $timeout, @_);
    $args{similarity_level} //= 47;
    bmwqemu::log_call(%args);
    $timeout   = bmwqemu::scale_timeout($args{timeout});
    $stilltime = $args{stilltime};
    if ($timeout < $stilltime) {
        bmwqemu::fctwarn("Selected timeout \'$timeout\' below stilltime \'$stilltime\', returning with false");
        return 0;
    }

    my $starttime      = time;
    my $lastchangetime = [gettimeofday];
    query_isotovideo('backend_set_reference_screenshot');

    while (time - $starttime < $timeout) {
        my $sim = query_isotovideo('backend_similiarity_to_reference')->{sim};
        my $now = [gettimeofday];
        if ($sim < $args{similarity_level}) {

            # a change
            $lastchangetime = $now;
            query_isotovideo('backend_set_reference_screenshot');
        }
        if (($now->[0] - $lastchangetime->[0]) + ($now->[1] - $lastchangetime->[1]) / 1000000. >= $stilltime) {
            bmwqemu::fctres("detected same image for $stilltime seconds");
            return 1;
        }
        # with 'no_wait' actually wait a little bit not to waste too much CPU
        # corresponding to what check_screen/assert_screen also does
        # internally
        sleep($args{no_wait} ? 0.01 : 0.5);
    }
    $autotest::current_test->timeout_screenshot();
    bmwqemu::fctres("wait_still_screen timed out after $timeout");
    return 0;
}

=head1 test variable access

=head2 get_var

  get_var($variable [, $default ])

Returns content of test variable C<$variable> or the C<$default> given as second argument or C<undef>

=cut

sub get_var {
    my ($var, $default) = @_;
    return $bmwqemu::vars{$var} // $default;
}

=head2 get_required_var

  get_required_var($variable)

Similar to C<get_var> but without default value and throws exception if variable can not be retrieved.

=cut

sub get_required_var {
    my ($var) = @_;
    return $bmwqemu::vars{$var} // croak "Could not retrieve required variable $var";
}

=head2 set_var

  set_var($variable, $value [, reload_needles => 1] );

Set test variable C<$variable> to value C<$value>.

Specify a true value for the C<reload_needles> flag to trigger a reloading
of needles in the backend and call the cleanup handler with the new variables
to make sure that possibly deselected needles are now taken into account
(useful if you change scenarios during the test run)

=cut

sub set_var {
    my ($var, $val, %args) = @_;
    $bmwqemu::vars{$var} = $val;
    if ($args{reload_needles}) {
        bmwqemu::save_vars();
        query_isotovideo('backend_reload_needles', {});
    }
    return;
}


=head2 check_var

  check_var($variable, $value);

Returns true if test variable C<$variable> is equal to C<$value> or returns C<undef>.

=cut

sub check_var {
    my ($var, $val) = @_;
    return 1 if (defined $bmwqemu::vars{$var} && $bmwqemu::vars{$var} eq $val);
    return 0;
}

=head2 get_var_array

  get_var_array($variable [, $default ]);

Return the given variable as array reference (split variable value by , | or ; )

=cut

sub get_var_array {
    my ($var, $default) = @_;
    my @vars = split(/,|;/, $bmwqemu::vars{$var} || '');
    return $default if !@vars;
    return \@vars;
}

=head2 check_var_array

  check_var_array($variable, $value);

Boolean function to check if a value list contains a value

=cut

sub check_var_array {
    my ($var, $val) = @_;
    my $vars_r = get_var_array($var);
    return grep { $_ eq $val } @$vars_r;
}

=head1 script execution helpers

=for stopwords os-autoinst autoinst isotovideo VNC

=head2 is_serial_terminal

  is_serial_terminal;

Determines if communication with the guest is being performed purely over a
serial port. When true, the guest should have a tty attached to a serial port
and os-autoinst sends commands to it as text. This differs from when a text
console is selected in the guest, but VNC is being used to simulate key presses.

When a serial terminal is selected you will not be able to use functions which
rely on needles. This sub is not exported by default as most tests I<will not
benefit> from changing their behaviour depending on if communication happens
over serial or VNC.

For more info see consoles/virtio_console.pm and consoles/virtio_screen.pm.

=cut

sub is_serial_terminal {
    state $ret;
    state $last_seen = '';
    if (defined $selected_console && $selected_console ne $last_seen) {
        $last_seen = $selected_console;
        $ret = query_isotovideo('backend_is_serial_terminal', {});
    }
    return $ret->{yesorno};
}


=head2 wait_serial

  wait_serial($regex or ARRAYREF of $regexes [[, $timeout], $expect_not_found]);

Wait for C<$regex> or anyone of C<$regexes> to appear on serial output.

Returns the string matched or C<undef> if C<$expect_not_found> is false
(default).

Returns C<undef> or (after timeout) the string that I<did _not_ match> if
C<$expect_not_found> is true.

=cut

sub wait_serial {

    # wait for a message to appear on serial output
    my $regexp           = shift;
    my $timeout          = shift || 90;    # seconds
    my $expect_not_found = shift || 0;     # expected can not found the term in serial output

    my %nargs = (@_, (regexp => $regexp, timeout => $timeout));

    bmwqemu::log_call(%nargs);
    $nargs{timeout} = bmwqemu::scale_timeout($nargs{timeout});

    my $ret = query_isotovideo('backend_wait_serial', \%nargs);
    my $matched = $ret->{matched};

    if ($expect_not_found) {
        $matched = !$matched;
    }
    bmwqemu::wait_for_one_more_screenshot() unless is_serial_terminal;

    # to string, we need to feed string of result to
    # record_serialresult()
    $matched = $matched ? 'ok' : 'fail';
    # convert dos2unix (poo#20542)
    $ret->{string} =~ s,\r\n,\n,g;
    $autotest::current_test->record_serialresult(bmwqemu::pp($regexp), $matched, $ret->{string});
    bmwqemu::fctres("$regexp: $matched");
    return $ret->{string} if ($matched eq "ok");
    return;    # false
}

=head2 x11_start_program

    x11_start_program($program[, @args]);

Start C<$program> in graphical desktop environment.

I<The implementation is distribution specific and not always available.>

=cut

sub x11_start_program {
    my ($program, @args) = @_;
    bmwqemu::log_call(program => $program, @args);
    return $distri->x11_start_program($program, @args);
}

sub _handle_script_run_ret {
    my ($ret, $cmd, %args) = @_;
    croak "command '$cmd' timed out" unless (defined $ret);
    my $die_msg = "command '$cmd' failed";
    $die_msg .= ": $args{fail_message}" if $args{fail_message};
    croak $die_msg unless ($ret == 0);
}

=head2 assert_script_run

  assert_script_run($cmd [, timeout => $timeout] [, fail_message => $fail_message]);

Deprecated mode

  assert_script_run($cmd [, $timeout [, $fail_message]]);

Run C<$cmd> via C<$distri->script_run> and C<die> unless it returns zero (indicating
successful completion of C<$cmd>). Default timeout is 90 seconds.
Use C<script_run> instead if C<$cmd> may fail.

C<$fail_message> is returned in the die message if specified.

I<The C<script_run> implementation is distribution specific and not always available.
For this to work correctly, it must return 0 if and only if C<$command> completes
successfully. It must NOT return 0 if C<$command> times out. The default implementation
should work on *nix operating systems with a configured serial device.>

=cut

sub assert_script_run {
    my ($cmd) = shift;
    my %args;
    if (@_ == 1) {
        %args = (timeout => $_[0]);
    }
    elsif (@_ == 2 && $_[0] ne 'fail_message' && $_[0] ne 'timeout') {
        %args = (timeout => $_[0], fail_message => $_[1]);
    }
    else {
        %args = @_;
    }
    # assert_script_run originally had the implicit default timeout of
    # wait_serial which we are repeating here to preserve old behaviour and
    # not change default timeout.
    $args{timeout} //= 90;
    bmwqemu::log_call(cmd => $cmd, wait => $args{timeout}, fail_message => $args{fail_message});
    my $ret = $distri->script_run($cmd, $args{timeout});
    _handle_script_run_ret($ret, $cmd, %args);
    return;
}

=head2 script_run

  script_run($cmd [, $wait]);

Run C<$cmd> (in the default implementation, by assuming the console prompt and typing
the command). If $wait_seconds is greater than 0, wait for that length of time for
execution to complete (otherwise, returns undef immediately). See C<distri->script_run>
for default timeout.

<Returns> exit code received from I<$cmd>, or undef if $wait_seconds is 0 or execution
does not complete within $wait_seconds.

I<The implementation is distribution specific and not always available.>

The default implementation should work on *nix operating systems with a configured
serial device so long as the user has permissions to write to the supplied serial
device C<$serialdev>.

=cut

sub script_run {
    my ($cmd, $wait) = @_;

    bmwqemu::log_call(cmd => $cmd, wait => $wait);
    return $distri->script_run($cmd, $wait);
}

=head2 assert_script_sudo

  assert_script_sudo($command [, $wait]);

Run C<$command> via C<script_sudo> and then check by C<wait_serial> if its exit
status is not zero.
See C<wait_serial> for default timeout.

I<The implementation is distribution specific and not always available.>

Make sure the non-root user has permissions to write to the supplied serial device
C<$serialdev>.

=cut

sub assert_script_sudo {
    my ($cmd, $wait) = @_;
    my $str = hashed_string("ASS$cmd");
    script_sudo("$cmd; echo $str-\$?- > /dev/$serialdev", 0);
    my $ret = wait_serial("$str-\\d+-", $wait);
    $ret = ($ret =~ /$str-(\d+)-/)[0] if $ret;
    _handle_script_run_ret($ret, $cmd);
    return;
}


=head2 script_sudo

  script_sudo($program [, $wait]);

Run C<$program> using sudo. Handle the sudo timeout and send password when appropriate.
C<$wait> defaults to 2 seconds.

I<The implementation is distribution specific and not always available.>

=cut

sub script_sudo {
    my $name = shift;
    my $wait = shift // 2;

    bmwqemu::log_call(name => $name, wait => $wait);
    return $distri->script_sudo($name, $wait);
}

=for stopwords SUT

=head2 script_output

  script_output($script [, $wait, type_command => 1])

Executing script inside SUT with C<bash -eox> (in case of serial console with C<bash -eo>)
and directs C<stdout> (I<not> C<stderr>!) to the serial console and returns
the output I<if> the script exits with 0. Otherwise the test is set to failed.

The script content is based on the variable content of C<current_test_script>
and is typed or fetched through HTTP depending on various parameters. Typing
can be forced by passing C<type_command => 1> for example when the SUT does
not provide a usable network connection.

The default timeout for the script is based on the default in C<wait_serial>
and can be tweaked by setting the C<$wait> positional parameter.

=cut

sub script_output {
    return $distri->script_output(@_);
}


=head2 save_tmp_file

  save_tmp_file($relpath, $content)

Saves content to the file in the worker pool directory using hash of the path,
including file, so it can be fetched via http later on using
 C< <autoinst_url>/files/#path_to_the_file> > url.
Can be used to modify files for specific test needs, e.g. autoinst profiles.
Dies if cannot open file for writing.

Example:
  save_tmp_file('autoyast/autoinst.xml', '<profile>Test</profile>')
Then the file can be fetched using url:
C< <autoinst_url>/files/autoyast/autoinst.xml> >

=cut

sub save_tmp_file {
    my ($relpath, $content) = @_;
    my $path = hashed_string($relpath);

    bmwqemu::log_call(path => $relpath);
    open my $fh, ">", $path;
    print $fh $content;
    close $fh;
}

=head2 get_test_data

  get_test_data($relpath)

Returns content of the file located in data directory. This method can be used
if one needs to modify files content before accessing it in SUT.

Example:
  get_test_data('autoyast/autoinst.xml')
This will return content of the file located in data/autoyast/autoinst.xml

=cut

sub get_test_data {
    my ($path) = @_;
    $path = get_var('CASEDIR') . '/data/' . $path;
    bmwqemu::log_call(path => $path);
    unless (-e $path) {
        bmwqemu::diag("File doesn't exist: $path");
        return;
    }
    open my $fh, "<", $path;
    my $content = do { local $/; <$fh> };
    close $fh;
    return $content;
}

=head2 validate_script_output

  validate_script_output($script, $code, [$wait])

Wrapper around script_output, that runs a callback on the output. Use it as

  validate_script_output "cat /etc/hosts", sub { m/127.*localhost/ }

=cut

sub validate_script_output($&;$) {
    my ($script, $code, $wait) = @_;
    $wait ||= 30;

    my $output = script_output($script, $wait);
    my $res = 'ok';

    # set $_ so the callbacks can be simpler code
    $_ = $output;
    if (!$code->()) {
        $res = 'fail';
        bmwqemu::diag("output does not pass the code block:\n$output");
    }
    # abusing the function
    $autotest::current_test->record_serialresult($output, $res, $output);
    if ($res eq 'fail') {
        croak "output not validating";
    }
}

=head2 become_root

  become_root;

Open a root shell.

I<The implementation is distribution specific and not always available.>

=cut

sub become_root {
    return $distri->become_root;
}

=head2 ensure_installed

  ensure_installed $package;

Helper to install a package to SUT.

I<The implementation is distribution specific and not always available.>

=cut

sub ensure_installed {
    return $distri->ensure_installed(@_);
}

=head2 hashed_string

  hashed_string();

Return a short string representing the given string by passing it through the
MD5 algorithm and taking the first characters.

=cut

sub hashed_string {
    my ($string, $count) = @_;
    $count //= 5;

    my $hash = md5_base64($string);
    # + and / are problematic in regexps and shell commands
    $hash =~ s,\+,_,g;
    $hash =~ s,/,~,g;
    return substr($hash, 0, $count);
}

=head1 keyboard support

=head2 send_key

  send_key($key [, $do_wait]);

Send one C<$key> to SUT keyboard input.

Special characters naming:

  'esc', 'down', 'right', 'up', 'left', 'equal', 'spc',  'minus', 'shift', 'ctrl'
  'caps', 'meta', 'alt', 'ret', 'tab', 'backspace', 'end', 'delete', 'home', 'insert'
  'pgup', 'pgdn', 'sysrq', 'super'

=cut

sub send_key {
    my ($key, $do_wait) = @_;
    $do_wait //= 0;
    bmwqemu::log_call(key => $key, do_wait => $do_wait);
    query_isotovideo('backend_send_key', {key => $key});
    wait_idle() if $do_wait;
}

=head2 hold_key

  hold_key($key);

Hold one C<$key> until release it

=cut

sub hold_key {
    my ($key) = @_;
    bmwqemu::log_call('hold_key', key => $key);
    query_isotovideo('backend_hold_key', {key => $key});
}

=head2 release_key

  release_key($key);

Release one C<$key> which is kept holding

=cut

sub release_key {
    my $key = shift;
    bmwqemu::log_call('release_key', key => $key);
    query_isotovideo('backend_release_key', {key => $key});
}

=head2 send_key_until_needlematch

  send_key_until_needlematch($tag, $key [, $counter, $timeout]);

Send specific key until needle with C<$tag> is not matched or C<$counter> is 0.
C<$tag> can be string or C<ARRAYREF> (C<['tag1', 'tag2']>)
Default counter is 20 steps, default timeout is 1s

Throws C<NeedleFailed> exception if needle is not matched until C<$counter> is 0.

=cut

sub send_key_until_needlematch {
    my ($tag, $key, $counter, $timeout) = @_;

    $counter //= 20;
    if (get_var('OFW')) {
        $timeout //= 3;
    }
    else {
        $timeout //= 1;
    }
    while (!check_screen($tag, $timeout)) {
        send_key $key;
        if (!$counter--) {
            assert_screen $tag, 1;
        }
    }
}

=head2 type_string

  type_string($string [, max_interval => <num> ] [, wait_screen_changes => <num> ] [, wait_still_screen => <num> ] [, secret => 1 ] );

send a string of characters, mapping them to appropriate key names as necessary

you can pass optional parameters with following keys:

C<max_interval (1-250)> determines the typing speed, the lower the
C<max_interval> the slower the typing.

C<wait_screen_change> if set, type only this many characters at a time
C<wait_screen_change> and wait for the screen to change between sets.

C<wait_still_screen> if set, C<wait_still_screen> for the given seconds
after the whole string is typed.

C<secret (bool)> suppresses logging of the actual string typed.

=cut

sub type_string {
    # special argument handling for backward compat
    my $string = shift;
    my %args;
    if (@_ == 1) {    # backward compat
        %args = (max_interval => $_[0]);
    }
    else {
        %args = @_;
    }
    my $log = $args{secret} ? 'SECRET STRING' : $string;

    if (is_serial_terminal) {
        bmwqemu::log_call(text => $log, %args);
        query_isotovideo('backend_type_string', {text => $string, %args});
        return;
    }

    my $max_interval = $args{max_interval} // 250;
    my $wait         = $args{wait_screen_change} // 0;
    my $wait_still   = $args{wait_still_screen} // 0;
    bmwqemu::log_call(string => $log, max_interval => $max_interval, wait_screen_changes => $wait, wait_still_screen => $wait_still);
    if ($wait) {
        # split string into an array of pieces of specified size
        # https://stackoverflow.com/questions/372370
        my @pieces = unpack("(a${wait})*", $string);
        for my $piece (@pieces) {
            wait_screen_change { query_isotovideo('backend_type_string', {text => $piece, max_interval => $max_interval}); };
            if ($wait_still) {
                wait_still_screen($wait_still);
            }
        }
    }
    else {
        query_isotovideo('backend_type_string', {text => $string, max_interval => $max_interval});
        if ($wait_still) {
            wait_still_screen($wait_still);
        }
    }
}

=head2 type_password

  type_password([$password]);

A convenience wrapper around C<type_string>, which doesn't log the string.

Uses C<$testapi::password> if no string is given.

=cut

sub type_password {
    my ($string, %args) = @_;
    $string //= $password;
    type_string $string, secret => 1, max_interval => ($args{max_interval} // 100);
}

=head1 mouse support

=head2 mouse_set

  mouse_set($x, $y);

Move mouse pointer to given coordinates

=cut

sub mouse_set {
    my ($mx, $my) = @_;

    bmwqemu::log_call(x => $mx, y => $my);
    query_isotovideo('backend_mouse_set', {x => $mx, y => $my});
}

=head2 mouse_click

  mouse_click([$button, $hold_time]);

Click mouse C<$button>. Can be C<'left'> or C<'right'>. Set C<$hold_time> to hold button for set time in seconds.
Default hold time is 1s

=cut

sub mouse_click {
    my $button = shift || 'left';
    my $time   = shift || 0.15;
    bmwqemu::log_call(button => $button, cursor_down => $time);
    query_isotovideo('backend_mouse_button', {button => $button, bstate => 1});
    # FIXME sleep resolution = 1s, use usleep
    sleep $time;
    query_isotovideo('backend_mouse_button', {button => $button, bstate => 0});
}

=head2 mouse_dclick

  mouse_dclick([$button, $hold_time]);

Same as mouse_click only for double click.

=cut

sub mouse_dclick(;$$) {
    my $button = shift || 'left';
    my $time   = shift || 0.10;
    bmwqemu::log_call(button => $button, cursor_down => $time);
    query_isotovideo('backend_mouse_button', {button => $button, bstate => 1});
    # FIXME sleep resolution = 1s, use usleep
    sleep $time;
    query_isotovideo('backend_mouse_button', {button => $button, bstate => 0});
    sleep $time;
    query_isotovideo('backend_mouse_button', {button => $button, bstate => 1});
    sleep $time;
    query_isotovideo('backend_mouse_button', {button => $button, bstate => 0});
}

=head2 mouse_tclick

  mouse_tclick([$button, $hold_time]);

Same as mouse_click only for triple click.

=cut

sub mouse_tclick(;$$) {
    my $button = shift || 'left';
    my $time   = shift || 0.10;
    bmwqemu::log_call(button => $button, cursor_down => $time);
    query_isotovideo('backend_mouse_button', {button => $button, bstate => 1});
    sleep $time;
    query_isotovideo('backend_mouse_button', {button => $button, bstate => 0});
    sleep $time;
    query_isotovideo('backend_mouse_button', {button => $button, bstate => 1});
    sleep $time;
    query_isotovideo('backend_mouse_button', {button => $button, bstate => 0});
    sleep $time;
    query_isotovideo('backend_mouse_button', {button => $button, bstate => 1});
    sleep $time;
    query_isotovideo('backend_mouse_button', {button => $button, bstate => 0});
}

=head2 mouse_hide

  mouse_hide([$border_offset]);

Hide mouse cursor by moving it out of screen area.

=cut

sub mouse_hide(;$) {
    my $border_offset = shift || 0;
    bmwqemu::log_call(border_offset => $border_offset);
    query_isotovideo('backend_mouse_hide', {offset => $border_offset});
}

=head1 multi console support

All C<testapi> commands that interact with the system under test do that
through a console.  C<send_key>, C<type_string> type into a console.
C<assert_screen> 'looks' at a console, C<assert_and_click> looks at
and clicks on a console.

Most backends support several consoles in some way.  These consoles
then have names as defined by the backend.

Consoles can be selected for interaction with the system under test.
One of them is 'selected' by default, as defined by the backend.

There are no consoles predefined by default, the distribution has
to add them during initial setup and define actions on what should
happen when they are selected first by the tests.

E.g. your distribution can give e.g. C<tty2> and C<tty4> a name for the
tests to select

  $self->add_console('root-console',  'tty-console', {tty => 2});
  $self->add_console('user-console',  'tty-console', {tty => 4});

=head2 add_console

  add_console("console", "console type" [, optional console parameters...])

You need to do this in your distribution and not in tests. It will not trigger
any action on the system under test, but only store the parameters.

The console parameters are console specific.

I<The implementation is distribution specific and not always available.>

=cut

require backend::console_proxy;
our %testapi_console_proxies;

=head2 select_console

    select_console($console [, @args]);

Example:

  select_console("root-console");

Select the named console for further C<testapi> interaction (send_text,
send_key, wait_screen_change, ...)

If this the first time, a test selects this console, the distribution
will get a call into activate_console('root-console', $console_obj, @args) to
make sure to actually log in root. For the backend it's just a C<tty>
object (in this example) - so it will ensure the console is active,
but to setup the root shell on this console, the distribution needs
to run test code.

After the console selection the distribution callback
C<$distri->console_selected> is called with C<@args>.

=cut

sub select_console {
    my ($testapi_console, @args) = @_;
    bmwqemu::log_call(testapi_console => $testapi_console, @args);
    if (!exists $testapi_console_proxies{$testapi_console}) {
        $testapi_console_proxies{$testapi_console} = backend::console_proxy->new($testapi_console);
    }
    my $ret = query_isotovideo('backend_select_console', {testapi_console => $testapi_console});
    die $ret->{error} if $ret->{error};

    $selected_console = $testapi_console;
    if ($ret->{activated}) {
        # we need to store the activated consoles for rollback
        if ($autotest::last_milestone) {
            push(@{$autotest::last_milestone->{activated_consoles}}, $testapi_console);
        }
        $testapi::distri->activate_console($testapi_console, @args);
    }
    $testapi::distri->console_selected($testapi_console, @args);

    return $testapi_console_proxies{$testapi_console};
}

=head2 console

  console("testapi_console")->$console_command(@console_command_args)

Some consoles have special commands beyond C<type_string>, C<assert_screen>

Such commands can be accessed using this API.

C<console("bootloader")>, C<console("errorlog")>, ... returns a proxy
object for the specific console which can then be directly accessed.

This is also useful for typing/interacting 'in the background',
without turning the video away from the currently selected console.

Note: C<assert_screen()> and friends look at the currently selected
console (select_console), no matter which console you send commands to
here.

=cut

sub console {
    my ($testapi_console) = @_;
    $testapi_console ||= $selected_console;
    bmwqemu::log_call(testapi_console => $testapi_console);
    if (!exists $testapi_console_proxies{$testapi_console}) {
        $testapi_console_proxies{$testapi_console} = backend::console_proxy->new($testapi_console);
    }
    return $testapi_console_proxies{$testapi_console};
}

=head2 reset_consoles

  reset_consoles;

will make sure the next select_console will activate the console. This is important
if you did something to the system that affects the console (e.g. trigger reboot).

=cut

sub reset_consoles {
    query_isotovideo('backend_reset_consoles');
    return;
}

=head1 audio support

=for stopwords qemu

=head2 start_audiocapture

  start_audiocapture;

Tells the backend to record a C<.wav> file of the sound card.

I<Only supported by qemu backend.>

=cut

sub start_audiocapture {
    my $fn = $autotest::current_test->capture_filename;
    my $filename = join('/', bmwqemu::result_dir(), $fn);
    bmwqemu::log_call(filename => $filename);
    return query_isotovideo('backend_start_audiocapture', {filename => $filename});
}

sub _check_or_assert_sound {
    my ($mustmatch, $check) = @_;

    my $result = $autotest::current_test->stop_audiocapture();
    my $wavfile = join('/', bmwqemu::result_dir(), $result->{audio});
    system("snd2png $wavfile $result->{audio}.png");

    my $imgpath = "$result->{audio}.png";

    return $autotest::current_test->verify_sound_image($imgpath, $mustmatch, $check);
}

=head2 assert_recorded_sound

  assert_recorded_sound('we-will-rock-you');

Tells the backend to record a C<.wav> file of the sound card and asserts if it matches
expected audio. Comparison is performed after conversion to the image.

I<Only supported by QEMU backend.>

=cut

sub assert_recorded_sound {
    my ($mustmatch) = @_;
    return _check_or_assert_sound $mustmatch;
}

=head2 check_recorded_sound

  check_recorded_sound('we-will-rock-you');

Tells the backend to record a C<.wav> file of the sound card and checks if it matches
expected audio. Comparison is performed after conversion to the image.

I<Only supported by QEMU backend.>

=cut

sub check_recorded_sound {
    my ($mustmatch) = @_;
    return _check_or_assert_sound $mustmatch, 1;
}

=head1 miscellaneous

=head2 power

  power($action);

Trigger backend specific power action, can be C<'on'>, C<'off'>, C<'acpi'> or C<'reset'>

=cut

sub power {

    # params: (on), off, acpi, reset
    my ($action) = @_;
    bmwqemu::log_call(action => $action);
    query_isotovideo('backend_power', {action => $action});
}

=head2 assert_shutdown

  assert_shutdown([$timeout]);

Periodically check backend for status until C<'shutdown'>. Does I<not> initiate shutdown.
Default timeout is 60s

Returns C<undef> on success, throws exception on timeout.

=cut

sub assert_shutdown {
    my ($timeout) = @_;
    $timeout //= 60;
    bmwqemu::log_call(timeout => $timeout);
    $timeout = bmwqemu::scale_timeout($timeout);
    while ($timeout >= 0) {
        my $is_shutdown = query_isotovideo('backend_is_shutdown') || 0;
        if ($is_shutdown < 0) {
            bmwqemu::diag("Backend does not implement is_shutdown - just sleeping");
            sleep($timeout);
        }
        # -1 counts too
        if ($is_shutdown) {
            $autotest::current_test->take_screenshot('ok');
            return;
        }
        sleep 1;
        --$timeout;
    }
    $autotest::current_test->take_screenshot('fail');
    croak "Machine didn't shut down!";
}

=head2 eject_cd

  eject_cd;

if backend supports it, eject the CD

=cut

sub eject_cd {
    bmwqemu::log_call();
    query_isotovideo('backend_eject_cd');
}

=head2 save_memory_dump

  save_memory_dump(filename => undef);

Saves the SUT memory state using C<$filename> as base for the memory dump
filename,  the default will be the current test's name.

This method must be called within a post_fail_hook.

I<Currently only qemu backend is supported.>

=cut

sub save_memory_dump {
    my %nargs = @_;
    $nargs{filename} ||= $autotest::current_test->{name};

    bmwqemu::log_call(%nargs);
    bmwqemu::diag("Trying to save machine state");

    query_isotovideo('backend_save_memory_dump', \%nargs);
}

=head2 save_storage_drives

  save_storage_drives([$filename]);

Saves all of the SUT drives using C<$filename> as part of the final filename,
the default will be the current test's name. The disk number will be always present.

This method must be called within a post_fail_hook.

I<Currently only qemu backend is supported.>

=cut

sub save_storage_drives {
    my $filename ||= $autotest::current_test->{name};
    die "save_storage_drives should be called within a post_fail_hook" unless ((caller(1))[3]) =~ /post_fail_hook/;

    bmwqemu::log_call();
    bmwqemu::diag("Trying to save machine drives");
    bmwqemu::load_vars();

    # Right now, we're saving all the disks
    # sometimes we might not want to. This could be improved.
    if (my $nd = $bmwqemu::vars{NUMDISKS}) {
        for my $i (1 .. $nd) {
            query_isotovideo('backend_save_storage_drives', {disk => $i, filename => $filename});
        }
    }
}

=head2 freeze_vm

  freeze_vm;

If the backend supports it, freeze the virtual machine. This will allow the
virtual machine to be paused/frozen within the test, but only from the
post_fail_hook. So that memory and disk dumps can be extracted without any
risk of data changing.

Call this method to ensure memory and disk dump refer to the same machine state.

I<Currently only qemu backend is supported.>

=cut

sub freeze_vm {
    #While it might be a good idea to allow the user to stop the vm within a test
    #we're not allowing them to do that outside a post_fail_hook.
    die "Method should be called within a post_fail_hook" unless ((caller(1))[3]) =~ /post_fail_hook/;
    bmwqemu::log_call();
    query_isotovideo('backend_freeze_vm');
}

=head2 resume_vm

  resume_vm;

If the backend supports it, resume the virtual machine. Call this method to
start virtual machine CPU explicitly if DELAYED_START is set.

I<Currently only qemu backend is supported.>

=cut

sub resume_vm {
    bmwqemu::log_call();
    query_isotovideo('backend_cont_vm');
}

=head2 parse_junit_log

=for stopwords jUnit

  parse_junit_log("report.xml");

Upload log file from SUT (calls upload_logs internally). The uploaded
file is then parsed as jUnit format and extra test results are created from it.

=cut

# XXX: To keep until tests are adapted
sub parse_junit_log { return parse_extra_log('JUnit', shift) }

=head2 parse_extra_log

=for stopwords extra_log

  parse_extra_log( Format => "report.xml" );

Upload log file from SUT (calls upload_logs internally). The uploaded
file is then parsed as the format supplied, that can be understood by OpenQA::Parser
 and extra test results are created from it.

 Formats currently supported are: JUnit, XUnit, LTP

=cut

sub parse_extra_log {
    my ($format, $file) = @_;

    $file = upload_logs($file);
    my @tests;

    {
        local $@;
        # We need to touch @INC as specific supported format are split
        # in different classes and dynamically loaded by OpenQA::Parser
        local @INC = (OPENQA_LIBPATH, @INC);
        eval {
            require OpenQA::Parser;
            OpenQA::Parser->import('parser');
            my $parser = parser($format => "ulogs/$file");
            $parser->write_output(bmwqemu::result_dir());
            $parser->write_test_result(bmwqemu::result_dir());

            $parser->tests->each(
                sub {
                    push(@tests, $_->to_openqa);
                });
        };
        croak $@ if $@;
    }

    return $autotest::current_test->register_extra_test_results(\@tests);
}

=head2 wait_idle

  wait_idle([$timeout_sec]);

B<Deprecated: > It is recommended to avoid the use of C<wait_idle>. See
L<https://progress.opensuse.org/issues/5830> for details.

This function will basically just sleep some time as this is the only viable
option considering all backend implementations. Previously this function tried
to wait until a test system becomes idle or timeout which only reliably worked
on qemu backend and was just sleeping on other backends. As such it is wasting
a lot of time and should be avoided as such.

Default timeout is 19s.

=cut

sub wait_idle {
    my $timeout = shift || 19;
    $timeout = bmwqemu::scale_timeout($timeout);

    # report wait_idle calls while we work on
    # https://progress.opensuse.org/issues/5830
    cluck "DEPRECATED: wait_idle called, update your test code";

    bmwqemu::log_call(timeout => $timeout);

    my $rsp = query_isotovideo('backend_wait_idle', {timeout => $timeout});
    bmwqemu::fctres("slept $timeout seconds");
    return;
}

=head1 log and data upload and download helpers

=for stopwords diag

=head2 diag

  diag('important message');

Write a diagnostic message to the logfile. In color, if possible.

=cut

sub diag {
    return bmwqemu::diag(@_);
}

=head2 host_ip
    Return VM's host IP
    in a kvm instance you reach the VM's host under 10.0.2.2
=cut
sub host_ip {
    return check_var('BACKEND', 'qemu') ? '10.0.2.2' : get_required_var('WORKER_HOSTNAME');
}

=head2 autoinst_url

  autoinst_url([$path, $query]);

returns the base URL to contact the local C<os-autoinst> service

Optional C<$path> argument is appended after base url.

Optional HASHREF C<$query> is converted to URL query and appended
after path.

Returns constructor URL. Can be used inline:

  script_run("curl " . autoinst_url . "/data");

=cut

sub autoinst_url {
    my ($path, $query) = @_;
    $path  //= '';
    $query //= {};
    my $hostname = host_ip();
    # QEMUPORT is historical for the base port of the worker instance
    my $workerport = get_var("QEMUPORT") + 1;

    my $token       = get_var('JOBTOKEN');
    my $querystring = join('&', map { "$_=$query->{$_}" } sort keys %$query);
    my $url         = "http://$hostname:$workerport/$token$path";
    $url .= "?$querystring" if $querystring;

    return $url;
}

=head2 data_url

  data_url($name);

returns the URL to download data or asset file
Special values REPO_\d and ASSET_\d points to the asset configured
in the corresponding variable

=cut

sub data_url($) {
    my ($name) = @_;
    if ($name =~ /^REPO_\d$/) {
        return autoinst_url("/assets/repo/" . get_var($name));
    }
    if ($name =~ /^ASSET_\d$/) {
        return autoinst_url("/assets/other/" . get_var($name));
    }
    else {
        return autoinst_url("/data/$name");
    }
}


=head2 upload_logs

=for stopwords GiB failok OpenQA WebUI

  upload_logs($file [, failok => 0, timeout => 90, log_name => "custom_name.log" ]);

Upload C<$file> to OpenQA WebUI as a log file and
return the uploaded file name. If failok is not set, a failed upload or
timeout will cause the test to die. Failed uploads happen if the file does not
exist or is over 20 GiB in size, so failok is useful when you just want
to upload the file if it exists but not mind if it doesn't. Default
timeout is 90s. C<log_name> parameter allow to control resulted job's attachment name.

=cut

sub upload_logs {
    my $file    = shift;
    my %args    = @_;
    my $failok  = $args{failok} || 0;
    my $timeout = $args{timeout} || 90;

    if (get_var('OFFLINE_SUT')) {
        record_info('upload skipped', "Skipped uploading log file '$file' as we are offline");
        return;
    }
    bmwqemu::log_call(file => $file, %args);
    my $basename = basename($file);
    my $upname   = ($args{log_name} || $autotest::current_test->{name}) . '-' . $basename;
    my $cmd      = "curl --form upload=\@$file --form upname=$upname ";
    $cmd .= autoinst_url("/uploadlog/$basename");
    if ($failok) {
        # just use script_run so we don't care if the upload fails
        script_run($cmd, $timeout);
    }
    else {
        assert_script_run($cmd, $timeout);
    }
    return $upname;
}

=head2 upload_asset

=for stopwords svirt

  upload_asset $file [,$public[,$nocheck]];

Uploads C<$file> as asset to OpenQA WebUI

You can upload private assets only accessible by related jobs:

    upload_asset '/tmp/suse.ps';

Or you can upload public assets that will have a fixed filename
replacing previous assets - useful for external users:

    upload_asset '/tmp/suse.ps', 1;

If you just want to upload a file and verify that it was uploaded
correctly on your own (e.g. in svirt console we don't have a serial
line and can't rely on assert_script_run check), add an optional
C<$nocheck> parameter:

    upload_asset '/tmp/suse.ps', 1, 1;

=cut

sub upload_asset {
    my ($file, $public, $nocheck) = @_;

    if (get_var('OFFLINE_SUT')) {
        record_info('upload skipped', "Skipped uploading asset '$file' as we are offline");
        return;
    }
    bmwqemu::log_call(file => $file, public => $public, nocheck => $nocheck);
    my $cmd = "curl --form upload=\@$file ";
    $cmd .= "--form target=assets_public " if $public;
    my $basename = basename($file);
    $cmd .= autoinst_url("/upload_asset/$basename");
    if ($nocheck) {
        type_string("$cmd\n");
    }
    else {
        return assert_script_run($cmd);
    }
}

1;

# vim: set sw=4 et:
