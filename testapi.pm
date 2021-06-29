# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2021 SUSE LLC
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
use Mojo::Base -strict, -signatures;
use File::Basename qw(basename dirname);
use File::Path 'make_path';
use Time::HiRes qw(sleep gettimeofday tv_interval);
use autotest 'query_isotovideo';
use Mojo::DOM;
require IPC::System::Simple;
use autodie ':all';
use OpenQA::Exceptions;
use OpenQA::Isotovideo::NeedleDownloader;
use Digest::MD5 'md5_base64';
use Carp qw(cluck croak);
use MIME::Base64 'decode_base64';
use Scalar::Util qw(looks_like_number reftype);
use B::Deparse;

require bmwqemu;
use constant OPENQA_LIBPATH => '/usr/share/openqa/lib';

our @EXPORT = qw($realname $username $password $serialdev %cmd %vars

  get_var get_required_var check_var set_var get_var_array check_var_array autoinst_url

  send_key send_key_until_needlematch type_string type_password
  enter_cmd
  hold_key release_key

  assert_screen check_screen assert_and_dclick save_screenshot
  assert_and_click mouse_hide mouse_set mouse_click
  mouse_dclick mouse_tclick match_has_tag click_lastmatch mouse_drag

  assert_script_run script_run background_script_run
  assert_script_sudo script_sudo script_output validate_script_output

  start_audiocapture assert_recorded_sound check_recorded_sound

  select_console console reset_consoles current_console

  upload_asset data_url check_shutdown assert_shutdown parse_junit_log parse_extra_log upload_logs

  wait_screen_change assert_screen_change wait_still_screen assert_still_screen wait_serial
  record_soft_failure record_info force_soft_failure
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

our $last_matched_needle;

sub send_key;
sub check_screen;
sub type_string;
sub type_password;
sub enter_cmd;


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

=head2 _calculate_clickpoint

This subroutine is used to by several subroutines dealing with mouse clicks to calculate
a clickpoint, when only the needle area is available. It takes the area coordinates and
returns the center of that area. It is meant to be a helper subroutine not available 
to be used in tests.

=cut    

sub _calculate_clickpoint ($needle_to_use, $needle_area, $click_point) {
    # If there is no needle area defined, take it from the needle itself.
    if (!$needle_area) {
        $needle_area = $needle_to_use->{area}->[-1];
    }
    # If there is no clickpoint defined, or if it has been specifically defined as "center"
    # then calculate the click point as a central point of the specified area.
    if (!$click_point || $click_point eq 'center') {
        $click_point = {
            xpos => $needle_area->{w} / 2,
            ypos => $needle_area->{h} / 2,
        };
    }
    # Use the click point coordinates (which are relative numbers inside of the area)
    # to calculate the absolute click point position.
    my $x = int($needle_area->{x} + $click_point->{xpos});
    my $y = int($needle_area->{y} + $click_point->{ypos});
    return $x, $y;
}

=for stopwords xen hvc0 xvc0 ipmi ttyS

=head2 init

Used for internal initialization, do not call from tests.

=cut

sub init {
    if (get_var('OFW') || get_var('BACKEND', '') =~ /s390x|pvm_hmc/) {
        $serialdev = "hvc0";
    }
    elsif (get_var('SERIALDEV')) {
        $serialdev = get_var('SERIALDEV');
    }
    else {
        $serialdev = 'ttyS0';
    }
    return;
}

=for stopwords ProhibitSubroutinePrototypes

=head2 set_distribution

    set_distribution($distri);

Set distribution object.

You can use distribution object to implement distribution specific helpers.

=cut

sub set_distribution ($distri) {
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

=for stopwords softfail

  record_soft_failure([$reason]);

Record a soft failure on the current test modules result. The result will
still be counted as a success. Use this to mark where workarounds are applied.
Takes an optional C<$reason> string which is recorded in the log file. See
C<force_soft_failure> to forcefully override a failed test module status from
a C<post_fail_hook> or C<record_info> when the status should not be
influenced.

=cut

sub record_soft_failure ($reason) {
    bmwqemu::log_call(reason => $reason);

    $autotest::current_test->record_soft_failure_result($reason);
}

sub _is_valid_result ($result) {
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

sub record_info ($title, $output, %nargs) {
    $nargs{result} //= 'ok';
    die 'unsupported $result \'' . $nargs{result} . '\'' unless _is_valid_result($nargs{result});
    bmwqemu::log_call(title => $title, output => $output, %nargs);
    $autotest::current_test->record_resultfile($title, $output, %nargs);
}

=head2 force_soft_failure

=for stopwords softfail

  force_soft_failure([$reason]);

Similar to C<record_soft_failure> but can be used to override the test module
status to softfail from a C<post_fail_hook> if the module would be set to fail
otherwise. This can be used for easier tracking of known issues without
needing to handle failed tests a lot.

=cut

sub force_soft_failure ($reason) {
    bmwqemu::log_call(reason => $reason);

    $autotest::current_test->record_soft_failure_result($reason, force_status => 1);
}

sub _handle_found_needle ($foundneedle, $rsp, $tags) {
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


sub _check_backend_response ($rsp, $check, $timeout, $mustmatch) {
    my $tags = $rsp->{tags};
    if (my $foundneedle = $rsp->{found}) {
        return _handle_found_needle($foundneedle, $rsp, $tags);
    }
    elsif ($rsp->{timeout}) {
        my $method         = $check ? 'check_screen' : 'assert_screen';
        my $status_message = "match=" . join(',', @$tags) . " timed out after $timeout ($method)";
        bmwqemu::fctres($status_message);

        # add the final mismatch as 'unk' result to be able to create a new needle from it
        # note: add the screenshot only if configured to pause on timeout - otherwise we would
        #       record each failure twice
        my $failed_screens = $rsp->{failed_screens};
        my $final_mismatch = $failed_screens->[-1];
        if (query_isotovideo(is_configured_to_pause_on_timeout => {check => $check})) {
            my $current_test = $autotest::current_test;
            if ($final_mismatch) {
                $autotest::current_test->record_screenfail(
                    img     => tinycv::from_ppm(decode_base64($final_mismatch->{image})),
                    needles => $final_mismatch->{candidates},
                    tags    => $tags,
                    result  => 'unk',
                    frame   => $final_mismatch->{frame},
                );
            }
            else {
                bmwqemu::fctwarn("ran into $method timeout but there's no final mismatch - just taking a screenshot");
                $current_test->take_screenshot();
            }
            $current_test->save_test_result();
        }

        # do a special rpc call to isotovideo which will block if the test should be paused
        # (if the test should not be paused this call will return 0; on resume (after pause) it will return 1)
        query_isotovideo('report_timeout', {
                tags  => $tags,
                msg   => $status_message,
                check => $check,
        }) and return 'try_again';

        if ($check) {
            # only care for the last one
            $failed_screens = [$final_mismatch];
        }
        for my $l (@$failed_screens) {
            my $img    = tinycv::from_ppm(decode_base64($l->{image}));
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

sub _check_or_assert ($mustmatch, $check, %args) {
    die "no tags specified" if (!$mustmatch || (ref $mustmatch eq 'ARRAY' && scalar @$mustmatch == 0));
    die "current_test undefined" unless $autotest::current_test;

    $args{timeout} = bmwqemu::scale_timeout($args{timeout});

    while (1) {
        my $rsp = query_isotovideo('check_screen', {mustmatch => $mustmatch, check => $check, timeout => $args{timeout}, no_wait => $args{no_wait}});

        # check backend response
        # (implemented as separate function because it needs to call itself)
        my $backend_response = _check_backend_response($rsp, $check, $args{timeout}, $mustmatch);

        # return the response unless we should try again after resuming from paused state
        return $backend_response if (!$backend_response || $backend_response ne 'try_again');

        # download new needles
        OpenQA::Isotovideo::NeedleDownloader->new()->download_missing_needles($rsp->{new_needles} // []);

        # reload needles before trying again
        query_isotovideo('backend_reload_needles', {});
    }
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

Returns matched needle or throws C<FailedNeedle> exception if $timeout timeout
is hit. Default timeout is 30s.

=cut

sub assert_screen ($mustmatch, @) {
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

Returns matched needle or C<undef> if timeout is hit. Default timeout is 0s.

=cut

sub check_screen ($mustmatch, @) {
    my $timeout;
    $timeout = shift if (@_ % 2);
    my %args = (timeout => $timeout // 0, @_);
    bmwqemu::log_call(mustmatch => $mustmatch, %args);
    return _check_or_assert($mustmatch, 1, %args);
}

=head2 match_has_tag

  match_has_tag($tag);

Returns true (1) if last matched needle has C<$tag>, false (0) if last
matched needle does not have C<$tag>, and C<undef> if no needle has yet
been matched at the time of the call.

=cut

sub match_has_tag ($tag) {
    if ($last_matched_needle) {
        return $last_matched_needle->{needle}->has_tag($tag);
    }
    return;
}

=head2 assert_and_click

  assert_and_click($mustmatch [, timeout => $timeout] [, button => $button] [, clicktime => $clicktime ] [, dclick => 1 ] [, mousehide => 1 ]);

Wait for needle with C<$mustmatch> tag to appear on SUT screen. Then click
C<$button> at the "click_point" position as defined in the needle JSON file,
or - if the JSON has not explicit "click_point" - in the middle of the last
needle area. If C<$dclick> is set, do double click instead.  C<$mustmatch> can
be string or C<ARRAYREF> of strings (C<['tag1', 'tag2']>).  C<$button> is by
default C<'left'>. C<'left'> and C<'right'> is supported. If C<$mousehide> is
true then always move mouse to the 'hidden' position after clicking to prevent
to hide the area where user wants to assert/click in second step.

Throws C<FailedNeedle> exception if C<$timeout> timeout is hit. Default timeout is 30s.

=cut

sub assert_and_click ($mustmatch, %args) {
    $args{timeout} //= $bmwqemu::default_timeout;

    $last_matched_needle = assert_screen($mustmatch, $args{timeout});
    bmwqemu::log_call(mustmatch => $mustmatch, %args);

    my %click_args = map { $_ => $args{$_} } qw(button dclick mousehide);
    return click_lastmatch(%click_args);
}

=head2 click_lastmatch

  click_lastmatch([, button => $button] [, clicktime => $clicktime ] [, dclick => 1 ] [, mousehide => 1 ]);

Click C<$button> at the "click_point" position as defined in the needle JSON file
of the last matched needle, or - if the JSON has not explicit "click_point" -
in the middle of the last match area. If C<$dclick> is set, do double click
instead. Supported values for C<$button> are C<'left'> and C<'right'>, C<'left'>
is the default. If C<$mousehide> is true then always move mouse to the 'hidden'
position after clicking to prevent to disturb the area where user wants to
assert/click in second step, otherwise move the mouse back to its previous
position.

=cut

sub click_lastmatch (%args) {
    $args{button}    //= 'left';
    $args{dclick}    //= 0;
    $args{mousehide} //= 0;

    return unless $last_matched_needle;

    my $old_mouse_coords = query_isotovideo('backend_get_last_mouse_set');

    # determine click coordinates from the last area which has those explicitly specified
    my $relevant_area;
    my $relative_click_point;
    for my $area (reverse @{$last_matched_needle->{area}}) {
        next unless ($relative_click_point = $area->{click_point});
        $relevant_area = $area;
        last;
    }

    # Calculate the absolute click point.
    my ($x, $y) = _calculate_clickpoint($last_matched_needle, $relevant_area, $relative_click_point);
    bmwqemu::diag("clicking at $x/$y");
    mouse_set($x, $y);
    if ($args{dclick}) {
        mouse_dclick($args{button}, $args{clicktime});
    }
    else {
        mouse_click($args{button}, $args{clicktime});
    }

    # move mouse back to where it was before we clicked, or to the 'hidden' position if it had never been
    # positioned
    # note: We can not move the mouse instantly. Otherwise we might end up in a click-and-drag situation.
    sleep 1;
    if ($old_mouse_coords->{x} > -1 && $old_mouse_coords->{y} > -1 && !$args{mousehide}) {
        return mouse_set($old_mouse_coords->{x}, $old_mouse_coords->{y});
    }
    else {
        return mouse_hide();
    }
}

=head2 assert_and_dclick

  assert_and_dclick($mustmatch [, timeout => $timeout] [, button => $button] [, clicktime => $clicktime ] [, dclick => 1 ] [, mousehide => 1 ]);

Alias for C<assert_and_click> with C<$dclick> set.

=cut

sub assert_and_dclick ($mustmatch, %args) {
    $args{dclick} = 1;
    return assert_and_click($mustmatch, %args);
}

=head2 wait_screen_change

  wait_screen_change(CODEREF [,$timeout [, similarity_level => 50]]);

Wrapper around code that is supposed to change the screen. This is the
opposite to C<wait_still_screen>. Make sure to put the commands to change the
screen within the block to avoid races between the action and the screen
change. C<wait_screen_change> waits for a screen change after C<CODEREF> was
executed.

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

sub wait_screen_change : prototype($@) {
    my ($callback, $timeout, %args) = @_;
    $timeout ||= 10;
    $args{similarity_level} //= 50;

    bmwqemu::log_call(timeout => $timeout, %args);
    $timeout = bmwqemu::scale_timeout($timeout);

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

# Need to parse code reference and pass to the method explicitly as
# wait_screen_change uses prototype which expects code block as an argument
# This resolves compile time issues
sub assert_screen_change ($coderef, @args) {
    wait_screen_change(\&{$coderef}, @_) or die 'assert_screen_change failed to detect a screen change';
}


=head2 wait_still_screen

=for stopwords stilltime

  wait_still_screen([$stilltime | [stilltime => $stilltime]] [, $timeout] | [timeout => $timeout]] [, similarity_level => $similarity_level] [, no_wait => $no_wait]);

Wait until the screen stops changing.

See C<assert_screen> for C<$no_wait>.

Returns true if screen is not changed for given C<$stilltime> (in seconds) or undef on timeout.
Default timeout is 30s, default stilltime is 7s.

=cut

sub wait_still_screen ($stilltime, @) {
    my $timeout = (@_ % 2) ? shift : $bmwqemu::default_timeout;
    my %args    = (stilltime => $stilltime, timeout => $timeout, @_);
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

    my $sim = 0;
    while (time - $starttime < $timeout) {
        $sim = query_isotovideo('backend_similiarity_to_reference')->{sim};
        my $now = [gettimeofday];
        if ($sim < $args{similarity_level}) {

            # a change
            $lastchangetime = $now;
            query_isotovideo('backend_set_reference_screenshot');
        }
        if (($now->[0] - $lastchangetime->[0]) + ($now->[1] - $lastchangetime->[1]) / 1000000. >= $stilltime) {
            bmwqemu::fctres("detected same image for $stilltime seconds, last detected similarity is $sim");
            return 1;
        }
        # with 'no_wait' actually wait a little bit not to waste too much CPU
        # corresponding to what check_screen/assert_screen also does
        # internally
        sleep($args{no_wait} ? 0.01 : 0.5);
    }
    $autotest::current_test->timeout_screenshot();
    bmwqemu::fctres("wait_still_screen timed out after $timeout, last detected similarity is $sim");
    return 0;
}

=head2 assert_still_screen

  assert_still_screen([$args...])

Run C<wait_still_screen> but C<die> if screen changed within timeout. Look
into C<wait_still_screen> for details.

=cut

sub assert_still_screen(@) {
    wait_still_screen(@_) or die 'assert_still_screen failed to detect a still screen';
}

=head1 test variable access

=head2 get_var

  get_var($variable [, $default ])

Returns content of test variable C<$variable> or the C<$default> given as second argument or C<undef>

=cut

sub get_var ($var, $default) {
    return $bmwqemu::vars{$var} // $default;
}

=head2 get_required_var

  get_required_var($variable)

Similar to C<get_var> but without default value and throws exception if variable can not be retrieved.

=cut

sub get_required_var ($var) {
    return $bmwqemu::vars{$var} // croak "Could not retrieve required variable $var";
}

=head2 set_var

  set_var($variable, $value [, reload_needles => 1] );

Set test variable C<$variable> to value C<$value>.
Variables starting with C<_SECRET_> will not appear in the C<vars.json> file.

Specify a true value for the C<reload_needles> flag to trigger a reloading
of needles in the backend and call the cleanup handler with the new variables
to make sure that possibly deselected needles are now taken into account
(useful if you change scenarios during the test run)

=cut

sub set_var ($var, $val, %args) {
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

sub check_var ($var, $val) {
    return 1 if (defined $bmwqemu::vars{$var} && $bmwqemu::vars{$var} eq $val);
    return 0;
}

=head2 get_var_array

  get_var_array($variable [, $default ]);

Return the given variable as array reference (split variable value by , | or ; )

=cut

sub get_var_array ($var, $default) {
    my @vars    = split(/,|;/, $bmwqemu::vars{$var} || '');
    my @default = split(/,|;/, $default             || '');
    return \@default if !@vars;
    return \@vars;
}

=head2 check_var_array

  check_var_array($variable, $value);

Boolean function to check if a value list contains a value

=cut

sub check_var_array ($var, $val) {
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

For more info see consoles/virtio_console.pm and consoles/serial_screen.pm.

=cut

sub is_serial_terminal() {
    state $ret;
    state $last_seen = '';
    if (defined current_console() && current_console() ne $last_seen) {
        $last_seen = current_console();
        $ret       = query_isotovideo('backend_is_serial_terminal', {});
    }
    return $ret->{yesorno};
}


=head2 wait_serial

  wait_serial($regex or ARRAYREF of $regexes, [, timeout => $timeout] [, expect_not_found => $expect_not_found] [, %args]);

Deprecated mode

  wait_serial($regex or ARRAYREF of $regexes [, $timeout [, $expect_not_found [, @args ]]]);

Wait for C<$regex> or anyone of C<$regexes> to appear on serial output.

Setting C<$no_regex> will cause it to do a plain string search.

Set C<$quiet>, to avoid recording serial_result.

For serial_terminal there are more options available, like C<record_output>,
C<buffer_size>. See C<consoles::serial_screen::read_unitl> for details.

Returns the string matched or C<undef> if C<$expect_not_found> is false
(default).

Returns C<undef> or (after timeout) the string that I<did _not_ match> if
C<$expect_not_found> is true. The default timeout is 90 seconds.

=cut

sub wait_serial ($regexp) {
    my %args = compat_args(
        {
            regexp           => $regexp,
            timeout          => 90,
            expect_not_found => 0,
            quiet            => undef,
            no_regex         => 0,
            buffer_size      => undef,
            record_output    => undef,
        }, ['timeout', 'expect_not_found'], @_);

    bmwqemu::log_call(%args);
    $args{timeout} = bmwqemu::scale_timeout($args{timeout});

    my $ret     = query_isotovideo('backend_wait_serial', \%args);
    my $matched = $ret->{matched};

    if ($args{expect_not_found}) {
        $matched = !$matched;
    }
    bmwqemu::wait_for_one_more_screenshot() unless is_serial_terminal;

    # to string, we need to feed string of result to
    # record_serialresult()
    $matched = $matched ? 'ok' : 'fail';
    # convert dos2unix (poo#20542)
    # hyperv and vmware (backend/svirt.pm) connect serial line over TCP/IP (socat)
    # convert CRLF to LF only
    $ret->{string} =~ s,\r\n,\n,g;
    $autotest::current_test->record_serialresult(bmwqemu::pp($regexp), $matched, $ret->{string}) unless ($args{quiet});
    bmwqemu::fctres("$regexp: $matched");
    return $ret->{string} if ($matched eq "ok");
    return;    # false
}

=head2 x11_start_program

    x11_start_program($program[, @args]);

Start C<$program> in graphical desktop environment.

I<The implementation is distribution specific and not always available.>

=cut

sub x11_start_program ($program, @args) {
    bmwqemu::log_call(program => $program, @args);
    return $distri->x11_start_program($program, @args);
}

sub _handle_script_run_ret ($ret, $cmd, %args) {
    croak "command '$cmd' timed out" unless (defined $ret);
    my $die_msg = "command '$cmd' failed";
    $die_msg .= ": $args{fail_message}" if $args{fail_message};
    croak $die_msg unless ($ret == 0);
}

=head2 assert_script_run

  assert_script_run($cmd [, timeout => $timeout] [, fail_message => $fail_message] [,quiet => $quiet]);

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

sub assert_script_run ($cmd, @) {
    my %args = compat_args(
        {
            # assert_script_run originally had the implicit default timeout of
            # wait_serial which we are repeating here to preserve old behaviour and
            # not change default timeout.
            timeout      => 90,
            fail_message => '',
            quiet        => testapi::get_var('_QUIET_SCRIPT_CALLS')
        }, ['timeout', 'fail_message'], @_);

    bmwqemu::log_call(cmd => $cmd, %args);
    my $ret = $distri->script_run($cmd, timeout => $args{timeout}, quiet => $args{quiet});
    _handle_script_run_ret($ret, $cmd, %args);
    return;
}

=head2 script_run

  script_run($cmd [, timeout => $timeout] [, output => ''] [, quiet => $quiet]);

Deprecated mode

  script_run($cmd [, $timeout]);

Run C<$cmd> (in the default implementation, by assuming the console prompt and typing
the command). If C<$timeout> is greater than 0, wait for that length of time for
execution to complete (otherwise, returns undef immediately). See C<distri->script_run>
for default timeout.

C<$output> can be used as an explanatory text that will be displayed with the execution of
the command.

<Returns> exit code received from I<$cmd>, or undef if $timeout is 0 or execution
does not complete within $timeout.

I<The implementation is distribution specific and not always available.>

The default implementation should work on *nix operating systems with a configured
serial device so long as the user has permissions to write to the supplied serial
device C<$serialdev>.

=cut

sub script_run ($cmd, @) {
    my %args = compat_args(
        {
            timeout => undef,
            output  => '',
            quiet   => testapi::get_var('_QUIET_SCRIPT_CALLS')
        }, ['timeout'], @_);

    bmwqemu::log_call(cmd => $cmd, %args);
    return $distri->script_run($cmd, %args);
}

=head2 background_script_run

  background_script_run($cmd [, output => ''] [, quiet => $quiet]);

Run C<$cmd> in background without waiting for it to finish. Remember to redirect output,
otherwise the PID marker may get corrupted.

C<$output> can be used as an explanatory text that will be displayed with the execution of
the command.

<Returns> PID of the I<$cmd> process running in the background.

I<The implementation is distribution specific and not always available.>

The default implementation should work on *nix operating systems with a configured
serial device so long as the user has permissions to write to the supplied serial
device C<$serialdev>.

=cut

sub background_script_run ($cmd, %args) {

    bmwqemu::log_call(cmd => $cmd, %args);
    return $distri->background_script_run($cmd, %args);
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

sub assert_script_sudo ($cmd, $wait) {
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

sub script_sudo ($name, $wait = 2) {
    bmwqemu::log_call(name => $name, wait => $wait);
    return $distri->script_sudo($name, $wait);
}

=for stopwords SUT

=head2 script_output

  script_output($script [, $wait, type_command => 1, proceed_on_failure => 1] [,quiet => $quiet])

Executing script inside SUT with C<bash -eox> (in case of serial console with C<bash -eo>)
and directs C<stdout> (I<not> C<stderr>!) to the serial console and returns
the output I<if> the script exits with 0. Otherwise the test is set to failed.
NOTE: execution result may include extra serial output which was on serial console
since command was triggered in case serial console is not dedicated for
the script output only.

The script content is based on the variable content of C<current_test_script>
and is typed or fetched through HTTP depending on various parameters. Typing
can be forced by passing C<type_command => 1> for example when the SUT does
not provide a usable network connection.

C<proceed_on_failure> - allows to proceed with validation when C<$script> is
failing (return non-zero exit code)

The default timeout for the script is based on the default in C<wait_serial>
and can be tweaked by setting the C<$wait> positional parameter.

=cut

sub script_output ($script, @) {
    my %args = testapi::compat_args(
        {
            timeout            => undef,
            proceed_on_failure => undef,                                     # fail on error by default
            quiet              => testapi::get_var('_QUIET_SCRIPT_CALLS'),
            type_command       => undef,
        }, ['timeout'], @_);

    return $distri->script_output($script, %args);
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

sub save_tmp_file ($relpath, $content) {
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

sub get_test_data ($path) {
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

  validate_script_output($script, $code | $regexp [, timeout => $timeout] [,quiet => $quiet])

Deprecated mode

  validate_script_output($script, $code, [$wait])

Wrapper around script_output, that runs a callback on the output, or
alternatively matches a regular expression. Use it as

  validate_script_output "cat /etc/hosts", sub { m/127.*localhost/ };
  validate_script_output "cat /etc/hosts", qr/127.*localhost/;
  validate_script_output "cat /etc/hosts", sub { $_ !~ m/987.*somehost/ };

=cut

sub validate_script_output ($script, $check) {
    my %args = compat_args(
        {
            timeout => 30,
            quiet   => testapi::get_var('_QUIET_SCRIPT_CALLS')
        }, ['timeout'], @_);

    my $output = script_output($script, %args);
    my $res    = 'ok';

    my $message = '';
    if (reftype $check eq 'CODE') {
        # set $_ so the callbacks can be simpler code
        $_ = $output;
        if (!$check->()) {
            $res = 'fail';
            bmwqemu::diag("output does not pass the code block:\n$output");
        }
        my $deparse = B::Deparse->new("-p");
        $deparse->ambient_pragmas(warnings => [], strict => "all");
        my $body = $deparse->coderef2text($check);

        $message = sprintf
          "validate_script_output got:\n%s\n\nCheck function (deparsed code):\n%s",
          $output, $body;
    }
    elsif (reftype $check eq 'REGEXP') {
        if ($output !~ $check) {
            $res = 'fail';
            bmwqemu::diag("output does not match the regex:\n$output");
        }
        $message = sprintf
          "validate_script_output got:\n%s\n\nRegular expression:\n%s",
          $output, $check;
    }
    else {
        croak "Invalid use of validate_script_output(), second arg must be a coderef or regexp";
    }
    $autotest::current_test->record_resultfile(
        'validate_script_output', $message,
        result => $res,
    );
    if ($res eq 'fail') {
        croak "output not validating";
    }
    return 0;
}

=head2 become_root

  become_root;

Open a root shell.

I<The implementation is distribution specific and not always available.>

=cut

sub become_root() {
    return $distri->become_root;
}

=head2 ensure_installed

  ensure_installed $package;

Helper to install a package to SUT.

I<The implementation is distribution specific and not always available.>

=cut

sub ensure_installed(@) {
    return $distri->ensure_installed(@_);
}

=head2 hashed_string

  hashed_string();

Return a short string representing the given string by passing it through the
MD5 algorithm and taking the first characters.

=cut

sub hashed_string ($string, $count = 5) {
    my $hash = md5_base64($string);
    # + and / are problematic in regexps and shell commands
    $hash =~ s,\+,_,g;
    $hash =~ s,/,~,g;
    return substr($hash, 0, $count);
}

=head1 keyboard support

=head2 send_key

  send_key($key [, wait_screen_change => $wait_screen_change]);

Send one C<$key> to SUT keyboard input. Waits for the screen to change when
C<$wait_screen_change> is true.

Special characters naming:

  'esc', 'down', 'right', 'up', 'left', 'equal', 'spc',  'minus', 'shift', 'ctrl'
  'caps', 'meta', 'alt', 'ret', 'tab', 'backspace', 'end', 'delete', 'home', 'insert'
  'pgup', 'pgdn', 'sysrq', 'super'

=cut

sub send_key ($key, @) {
    my %args = (@_ == 1) ? (do_wait => +shift()) : @_;
    $args{do_wait}            //= 0;
    $args{wait_screen_change} //= 0;
    bmwqemu::log_call(key => $key, %args);
    if ($args{wait_screen_change}) {
        wait_screen_change {query_isotovideo('backend_send_key', {key => $key})};
    }
    else {
        query_isotovideo('backend_send_key', {key => $key});
    }
}

=head2 hold_key

  hold_key($key);

Hold one C<$key> until release it

=cut

sub hold_key ($key) {
    bmwqemu::log_call('hold_key', key => $key);
    query_isotovideo('backend_hold_key', {key => $key});
}

=head2 release_key

  release_key($key);

Release one C<$key> which is kept holding

=cut

sub release_key ($key) {
    bmwqemu::log_call('release_key', key => $key);
    query_isotovideo('backend_release_key', {key => $key});
}

=head2 send_key_until_needlematch

  send_key_until_needlematch($tag, $key [, $counter, $timeout]);

Send specific key until needle with C<$tag> is not matched or C<$counter> is 0.
C<$tag> can be string or C<ARRAYREF> (C<['tag1', 'tag2']>)
Default counter is 20 steps, default timeout is 1s

Throws C<FailedNeedle> exception if needle is not matched until C<$counter> is 0.

=cut

sub send_key_until_needlematch ($tag, $key, $counter = 20, $timeout = 1) {
    while (!check_screen($tag, $timeout)) {
        wait_screen_change {
            send_key $key;
        };
        if (!$counter--) {
            assert_screen $tag, 1;
        }
    }
}

=head2 type_string

  type_string($string [, max_interval => <num> ] [, wait_screen_changes => <num> ] [, wait_still_screen => <num> ] [, secret => 1 ]
  [, timeout => <num>] [, similarity_level => <num>] [, lf => 1 ]);

send a string of characters, mapping them to appropriate key names as necessary

you can pass optional parameters with following keys:

C<max_interval (1-250)> determines the typing speed, the lower the
C<max_interval> the slower the typing.

C<wait_screen_change> if set, type only this many characters at a time
C<wait_screen_change> and wait for the screen to change between sets.

C<wait_still_screen> if set, C<wait_still_screen> returns true if screen is not
changed for given C<$wait_still_screen> seconds or false if the screen is not still
for the given seconds within defined C<timeout> after the whole string is typed.
Default timeout is 30s, default stilltime is 0s.

C<similarity_level> can be passed as argument for wrapped C<wait_still_screen> calls.

C<secret (bool)> suppresses logging of the actual string typed.

C<lf (bool)> finishes the string with an additional line feed, for example to
enter a command line.

=cut

sub type_string ($string, @) {
    # special argument handling for backward compat
    my %args = @_ == 1       ? (max_interval => $_[0]) : @_;
    my $log  = $args{secret} ? 'SECRET STRING'         : $string;
    $string .= "\n" if $args{lf};

    if (is_serial_terminal) {
        bmwqemu::log_call(text => $log, %args);
        query_isotovideo('backend_type_string', {text => $string, %args});
        return;
    }

    my $max_interval   = $args{max_interval}       // 250;
    my $wait           = $args{wait_screen_change} // 0;
    my $wait_still     = $args{wait_still_screen}  // 0;
    my $wait_timeout   = $args{timeout}            // 30;
    my $wait_sim_level = $args{similarity_level}   // 47;
    bmwqemu::log_call(string => $log, max_interval => $max_interval, wait_screen_changes => $wait, wait_still_screen => $wait_still,
        timeout => $wait_timeout, similarity_level => $wait_sim_level);
    my @pieces;
    if ($wait) {
        # split string into an array of pieces of specified size
        # https://stackoverflow.com/questions/372370
        @pieces = unpack("(a${wait})*", $string);
    }
    else {
        push @pieces, $string;
    }
    for my $piece (@pieces) {
        if ($wait) {
            wait_screen_change {query_isotovideo('backend_type_string', {text => $piece, max_interval => $max_interval});};
        }
        else {
            query_isotovideo('backend_type_string', {text => $piece, max_interval => $max_interval});
        }
        if ($wait_still && !wait_still_screen(stilltime => $wait_still,
                timeout => $wait_timeout, similarity_level => $wait_sim_level)) {
            die "wait_still_screen timed out after ${wait_timeout}s!";
        }
    }
}

=head2 type_password

  type_password($password [, max_interval => <num> ] [, wait_screen_changes => <num> ] [, wait_still_screen => <num> ] [, timeout => <num>]
  [, similarity_level => <num>] );

A convenience wrapper around C<type_string>, which doesn't log the string.

Uses C<$testapi::password> if no string is given.

You can pass the same optional parameters as for C<type_string> function.

=cut

sub type_password ($string = $password, %args) {
    type_string $string, secret => 1, max_interval => ($args{max_interval} // 100), %args;
}

=head2 enter_cmd

  enter_cmd($string [, max_interval => <num> ] [, wait_screen_changes => <num> ] [, wait_still_screen => <num> ] [, secret => 1 ]
  [, timeout => <num>] [, similarity_level => <num>] );

A convenience wrapper around C<type_string>, that adds a linefeed to execute a
command within a command line prompt.

You can pass the same optional parameters as for C<type_string> function.

=cut

sub enter_cmd ($string, @) {
    type_string $string, lf => 1, @_;
}

=head1 mouse support

=head2 mouse_set

  mouse_set($x, $y);

Move mouse pointer to given coordinates

=cut

sub mouse_set ($mx, $my) {
    bmwqemu::log_call(x => $mx, y => $my);
    query_isotovideo('backend_mouse_set', {x => $mx, y => $my});
}

=head2 mouse_click

  mouse_click([$button, $hold_time]);

Click mouse C<$button>. Can be C<'left'> or C<'right'>. Set C<$hold_time> to hold button for set time in seconds.
Default hold time is 0.15s

=cut

sub mouse_click ($button, $time = 0.15) {
    bmwqemu::log_call(button => $button, cursor_down => $time);
    query_isotovideo('backend_mouse_button', {button => $button, bstate => 1});
    sleep $time;
    query_isotovideo('backend_mouse_button', {button => $button, bstate => 0});
}

=head2 mouse_dclick

  mouse_dclick([$button, $hold_time]);

Same as mouse_click only for double click.

=cut

sub mouse_dclick ($button, $time = 0.10) {
    bmwqemu::log_call(button => $button, cursor_down => $time);
    query_isotovideo('backend_mouse_button', {button => $button, bstate => 1});
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

sub mouse_tclick ($button, $time = 0.10) {
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

sub mouse_hide ($border_offset = 0) {
    bmwqemu::log_call(border_offset => $border_offset);
    query_isotovideo('backend_mouse_hide', {offset => $border_offset});
}

=head2 mouse_drag
  mouse_drag([$startpoint, $endpoint, $startx, $starty, $endx, $endy, $button, $timeout]);

Click mouse C<$button>, C<'left'> or C<'right'>, at a given location, hold the button and drag 
the mouse to another location where the button is released. You can set the C<$startpoint> 
and C<$endpoint> by passing the name of the needle tag, i.e. the mouse drag happens between
the two needle areas. Alternatively, you can set all the coordinates explicitly with C<$startx>,
C<$starty>, C<$endx>, and C<$endy>. You can also set one point using a needle and another one
using coordinates.  If both the coordinates and the needle are provided, the coordinates 
will be used to set up the locations and the needle location will be overridden.

=cut

sub mouse_drag (%args) {
    my ($startx, $starty, $endx, $endy);
    # If full coordinates are provided, work with them as a priority,
    if (defined $args{startx} and defined $args{starty}) {
        $startx = $args{startx};
        $starty = $args{starty};
    }
    # If the coordinates were not complete, use the needle as a fallback solution.
    elsif (defined $args{startpoint}) {
        my $startmatch = $args{startpoint};
        # Check that the needle exists.
        my $start_matched_needle = assert_screen($startmatch, $args{timeout});
        # Calculate the click point from the area defined by the needle (take the center of it)
        ($startx, $starty) = _calculate_clickpoint($start_matched_needle);
    }
    # If neither coordinates nor a needle is provided, report an error and quit.
    else {
        die "The starting point of the drag was not correctly provided. Either provide the 'startx' and 'starty' coordinates, or a needle marking the starting point.";
    }

    # Repeat the same for endpoint coordinates or needles.
    if (defined $args{endx} and defined $args{endy}) {
        $endx = $args{endx};
        $endy = $args{endy};
    }
    elsif (defined $args{endpoint}) {
        my $endmatch           = $args{endpoint};
        my $end_matched_needle = assert_screen($endmatch, $args{timeout});
        ($endx, $endy) = _calculate_clickpoint($end_matched_needle);
    }
    else {
        die "The ending point of the drag was not correctly provided. Either provide the 'endx' and 'endy' coordinates, or a needle marking the end point.";
    }
    # Get the button variable. If no button has been provided, assume the "left" button.
    my $button = $args{button} // "left";

    # Now, perform the actual mouse drag. Navigate to the startpoint location,
    # press and hold the mouse button, then navigate to the endpoint location
    # and release the mouse button.
    mouse_set($startx, $starty);
    query_isotovideo('backend_mouse_button', {button => $button, bstate => 1});
    mouse_set($endx, $endy);
    query_isotovideo('backend_mouse_button', {button => $button, bstate => 0});
    bmwqemu::log_call(message => "Mouse dragged from $startx,$starty to $endx, $endy", button => $button);
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

The console parameters are console specific. Parameter C<persistent> skips
console reset and console is persistent during the test execution.

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

sub select_console ($testapi_console, @args) {
    bmwqemu::log_call(testapi_console => $testapi_console, @args);
    if (!exists $testapi_console_proxies{$testapi_console}) {
        $testapi_console_proxies{$testapi_console} = backend::console_proxy->new($testapi_console);
    }
    my $ret = query_isotovideo('backend_select_console', {testapi_console => $testapi_console});
    die $ret->{error} if $ret->{error};

    $autotest::selected_console = $testapi_console;
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

sub console ($testapi_console) {
    $testapi_console ||= current_console();
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

sub reset_consoles() {
    query_isotovideo('backend_reset_consoles');
    return;
}

=head2
    current_console

Return the currently selected console, a call when no console is selected, will
return C<undef>.

=cut

sub current_console() {
    return $autotest::selected_console;
}

=head1 audio support

=for stopwords qemu

=head2 start_audiocapture

  start_audiocapture;

Tells the backend to record a C<.wav> file of the sound card.

I<Only supported by qemu backend.>

=cut

sub start_audiocapture ($fn) {
    my $filename = join('/', bmwqemu::result_dir(), $fn);
    bmwqemu::log_call(filename => $filename);
    return query_isotovideo('backend_start_audiocapture', {filename => $filename});
}

sub _check_or_assert_sound ($mustmatch, $check) {
    my $result  = $autotest::current_test->stop_audiocapture();
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

sub assert_recorded_sound ($mustmatch) {
    return _check_or_assert_sound $mustmatch;
}

=head2 check_recorded_sound

  check_recorded_sound('we-will-rock-you');

Tells the backend to record a C<.wav> file of the sound card and checks if it matches
expected audio. Comparison is performed after conversion to the image.

I<Only supported by QEMU backend.>

=cut

sub check_recorded_sound ($mustmatch) {
    return _check_or_assert_sound $mustmatch, 1;
}

=head1 miscellaneous

=head2 power

  power($action);

Trigger backend specific power action, can be C<'on'>, C<'off'>, C<'acpi'> or C<'reset'>

=cut

sub power ($action) {
    bmwqemu::log_call(action => $action);
    query_isotovideo('backend_power', {action => $action});
}

=head2 check_shutdown

  check_shutdown([$timeout]);

Periodically check backend for status until C<'shutdown'>. Does I<not> initiate shutdown.

Returns true on success and false if C<$timeout> timeout is hit. Default timeout is 60s.

=cut

sub check_shutdown ($timeout = 60) {
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
            return 1;
        }
        sleep 1;
        --$timeout;
    }
    return 0;
}

=head2 assert_shutdown

  assert_shutdown([$timeout]);

Periodically check backend for status until C<'shutdown'>. Does I<not> initiate shutdown.

Returns C<undef> on success, marks the test as failed and throws exception
if C<$timeout> timeout is hit. Default timeout is 60s.

=cut

sub assert_shutdown ($timeout = 60) {
    if (check_shutdown($timeout)) {
        $autotest::current_test->take_screenshot('ok');
        return;
    }
    else {
        $autotest::current_test->take_screenshot('fail');
        croak "Machine didn't shut down!";
    }
}

=head2 eject_cd

  eject_cd;

if backend supports it, eject the CD

=cut

sub eject_cd (%nargs) {
    bmwqemu::log_call(%nargs);
    query_isotovideo(backend_eject_cd => \%nargs);
}

=head2 save_memory_dump

  save_memory_dump(filename => undef);

Saves the SUT memory state using C<$filename> as base for the memory dump
filename,  the default will be the current test's name.

This method must be called within a post_fail_hook.

I<Currently only qemu backend is supported.>

=cut

sub save_memory_dump (%nargs) {
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

sub save_storage_drives ($filename = $autotest::current_test->{name}) {
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
virtual machine to be paused/frozen within the test, it is recommended to call
this within a C<post_fail_hook> so that memory and disk dumps can be extracted
without any risk of data changing, or in rare cases call it before the tests
tests have already begun, to avoid unexpected behaviour.

I<Currently only qemu backend is supported.>

=cut

sub freeze_vm() {
    # While it might be a good idea to allow the user to stop the vm within a test
    # we're not encouraging them to do that outside a post_fail_hook or at any point
    # in the test code.
    bmwqemu::diag "Call freeze_vm within a post_fail_hook or very early in your test"
      unless ((caller(1))[3]) =~ /post_fail_hook/;
    bmwqemu::log_call();
    query_isotovideo('backend_freeze_vm');
}

=head2 resume_vm

  resume_vm;

If the backend supports it, resume the virtual machine. Call this method to
start virtual machine CPU explicitly if DELAYED_START is set.

I<Currently only qemu backend is supported.>

=cut

sub resume_vm() {
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
sub parse_junit_log ($path) { return parse_extra_log('JUnit', $path) }

=head2 parse_extra_log

=for stopwords extra_log

  parse_extra_log( Format => "report.xml" );

Upload log file from SUT (calls upload_logs internally). The uploaded
file is then parsed as the format supplied, that can be understood by OpenQA::Parser
 and extra test results are created from it.

 Formats currently supported are: JUnit, XUnit, LTP

=cut

sub parse_extra_log ($format, $file) {
    $file = upload_logs($file);
    my @tests;

    {
        local $@;
        # We need to touch @INC as specific supported format are split
        # in different classes and dynamically loaded by OpenQA::Parser
        local @INC = ($ENV{OPENQA_LIBPATH} // OPENQA_LIBPATH, @INC);
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

=head1 log and data upload and download helpers

=for stopwords diag

=head2 diag

  diag('important message');

Write a diagnostic message to the logfile. In color, if possible.

=cut

sub diag(@) {
    return bmwqemu::diag(@_);
}

=head2 host_ip

=for stopwords kvm VM

    Return VM's host IP
    in a kvm instance you reach the VM's host under default 10.0.2.2
=cut
sub host_ip() {
    return check_var('BACKEND', 'qemu') ? get_var('QEMU_HOST_IP', '10.0.2.2') : get_required_var('WORKER_HOSTNAME');
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

sub autoinst_url ($path = '', $query = {}) {
    my $hostname = get_var('AUTOINST_URL_HOSTNAME', host_ip());
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

sub data_url ($name) {
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

sub upload_logs ($file, %args) {
    my $failok  = $args{failok}  || 0;
    my $timeout = $args{timeout} || 90;

    if (get_var('OFFLINE_SUT')) {
        record_info('upload skipped', "Skipped uploading log file '$file' as we are offline");
        return;
    }
    bmwqemu::log_call(file => $file, failok => $failok, timeout => $timeout, %args);
    my $basename = basename($file);
    my $upname   = $args{log_name} || ($autotest::current_test->{name} . '-' . $basename);
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

sub upload_asset ($file, $public = undef, $nocheck = undef) {
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

=head2 compat_args

Helper function to create backward compatible function arguments when moving
from positional arguments to named one.

    compat_args( $hash_ref_defaults, $arrayref_old_fixed, [ $arg1, $arg2, ...])

A typical call would look like:

    my %args = compat_args({timeout => 60, .. }, ['timeout'], @_);
=cut
sub compat_args ($def_args, $fix_keys, @) {
    my %ret;
    for my $key (@{$fix_keys}) {
        $ret{$key} = shift if (scalar(@_) >= 1 && (!defined($_[0]) || !grep(/^$_[0]$/, keys(%{$def_args}))));
    }
    carp("Odd number of arguments") unless ((@_ % 2) == 0);
    %ret = (%{$def_args}, %ret, @_);
    map { $ret{$_} //= $def_args->{$_} } keys(%{$def_args});
    return %ret;
}

1;
