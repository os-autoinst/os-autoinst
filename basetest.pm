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

package basetest;

use Mojo::Base -strict, -signatures;
use autodie ':all';

use bmwqemu ();
use ocr;
use POSIX;
use testapi  ();
use autotest ();
use MIME::Base64 'decode_base64';
use Mojo::File 'path';

my $serial_file_pos  = 0;
my $autoinst_log_pos = 0;

# enable strictures and warnings in all tests globaly
sub import {
    strict->import;
    warnings->import;
}

sub new ($class, $category) {
    $category ||= 'unknown';
    my $self = {class => $class};
    $self->{lastscreenshot}         = undef;
    $self->{details}                = [];
    $self->{result}                 = undef;
    $self->{running}                = 0;
    $self->{category}               = $category;
    $self->{test_count}             = 0;
    $self->{screen_count}           = 0;
    $self->{wav_fn}                 = undef;
    $self->{dents}                  = 0;
    $self->{post_fail_hook_running} = 0;
    $self->{timeoutcounter}         = 0;
    $self->{activated_consoles}     = [];
    $self->{name}                   = $class;
    $self->{serial_failures}        = [];
    $self->{autoinst_failures}      = [];
    $self->{fatal_failure}          = 0;
    $self->{execution_time}         = 0;
    return bless $self, $class;
}

=head1 Methods

=head2 run

Body of the test to be implemented by child classes.
This code is run during test.

=head2 is_applicable

Return false if the test should be skipped.

By default it checks the test name and fullname against a comma-separated
blocklist in C<EXCLUDE_MODULES> variable and returns false if it is found there.

If C<INCLUDE_MODULES> is set it will only return true for modules matching the
passlist specified in a comma-separated list in C<EXCLUDE_MODULES> matching
either test name or fullname.

C<EXCLUDE_MODULES> has precedence over C<INCLUDE_MODULES> and can be combined
to blocklist test modules from the passlist specified in C<INCLUDE_MODULES>.

Can eg. check vars{BIGTEST}, vars{LIVETEST}

=cut

sub is_applicable ($self) {
    if ($bmwqemu::vars{EXCLUDE_MODULES}) {
        my %excluded = map { $_ => 1 } split(/\s*,\s*/, $bmwqemu::vars{EXCLUDE_MODULES});

        return 0 if $excluded{$self->{class}};
        return 0 if $excluded{$self->{fullname}};
    }
    if ($bmwqemu::vars{INCLUDE_MODULES}) {
        my %included = map { $_ => 1 } split(/\s*,\s*/, $bmwqemu::vars{INCLUDE_MODULES});

        return 0 unless ($included{$self->{class}} || $included{$self->{fullname}});
    }
    return 1;
}

=head2 test_flags

Return a hash of flags that are either there or not

  'fatal'          - abort whole test suite if this fails (and set overall state 'failed')
  'ignore_failure' - if this module fails, it will not affect the overall result at all
  'milestone'      - after this test succeeds, update 'lastgood'
  'no_rollback'     - don't roll back to 'lastgood' snapshot if this fails
  'always_rollback' - roll back to 'lastgood' snapshot even if this does not fail

=cut

sub test_flags {
    return {};
}

=head2 post_fail_hook

Function is run after test has failed to e.g. recover log files

=cut

sub post_fail_hook {
    return 1;
}

=head2 _framenumber_to_timerange

Create a media fragment time from a given framenumber

=cut

sub _framenumber_to_timerange ($frame) {
    return [sprintf("%.2f", $frame / 24.0), sprintf("%.2f", ($frame + 1) / 24.0)];
}

sub record_screenmatch ($self, $img, $match, $tags = [], $failed_needles = [], $frame = undef) {
    my $serialized_match = $self->_serialize_match($match);
    my $properties       = $match->{needle}->{properties} || [];
    my $result           = {
        needle     => $serialized_match->{name},
        area       => $serialized_match->{area},
        error      => $serialized_match->{error},
        json       => $serialized_match->{json},
        tags       => [@$tags],                            # make a copy
        properties => [@$properties],                      # make a copy
        frametime  => _framenumber_to_timerange($frame),
        screenshot => $self->next_resultname('png'),
        result     => 'ok',
    };

    # make sure needle is blessed
    my $foundneedle = bless $match->{needle}, "needle";

    # When the needle has the workaround property,
    # mark the result as dent and increase the dents
    if (my $workaround = $foundneedle->has_property('workaround')) {
        $result->{dent}   = 1;
        $result->{result} = "softfail";

        # write a test result file
        my $reason = $foundneedle->get_property_value('workaround');
        $self->record_soft_failure_result($reason);

        bmwqemu::diag("needle '$serialized_match->{name}' is a workaround. The reason is $reason");
    }

    # also include the not matched needles
    my $candidates;
    for my $cand (@{$failed_needles || []}) {
        push @$candidates, $self->_serialize_match($cand);
    }
    $result->{needles} = $candidates if $candidates;

    my $fn = join('/', bmwqemu::result_dir(), $result->{screenshot});
    $img->write_with_thumbnail($fn);

    $self->{result} ||= 'ok';

    push @{$self->{details}}, $result;
    return $result;
}

=head2

serialize a match result from needle::search

=cut

sub _serialize_match ($self, $candidate) {
    my $name     = $candidate->{needle}->{name};
    my $jsonfile = $candidate->{needle}->{file};
    my %match    = (
        name  => $name,
        error => $candidate->{error},
        area  => [],
        json  => $jsonfile
    );

    if (my $unregistered = $candidate->{needle}->{unregistered}) {
        $match{unregistered} = $unregistered;
    }
    for my $area (@{$candidate->{area}}) {
        my $na = {};
        for my $i (qw(x y w h result)) {
            $na->{$i} = $area->{$i};
        }
        $na->{similarity}  = int($area->{similarity} * 100);
        $na->{click_point} = $area->{click_point} if exists $area->{click_point};
        push @{$match{area}}, $na;
    }

    return \%match;
}

sub record_screenfail ($self, %args) {
    my $img     = $args{img};
    my $needles = $args{needles} || [];
    my $tags    = $args{tags}    || [];
    my $status  = $args{result}  || 'fail';
    my $overall = $args{overall};    # whether and how to set global test result
    my $frame   = $args{frame};

    my $candidates;
    for my $cand (@{$needles || []}) {
        push @$candidates, $self->_serialize_match($cand);
    }

    my $result = {
        screenshot => $self->next_resultname('png'),
        result     => $status,
        frametime  => _framenumber_to_timerange($frame),
    };

    $result->{needles} = $candidates if $candidates;
    $result->{tags}    = [@$tags]    if $tags;         # make a copy

    my $fn = join('/', bmwqemu::result_dir(), $result->{screenshot});
    $img->write_with_thumbnail($fn);

    $self->{result} = $overall if $overall;

    push @{$self->{details}}, $result;
    return $result;
}

sub remove_last_result ($self) {
    --$self->{test_count};
    return pop @{$self->{details}};
}

sub details ($self) {
    return $self->{details};
}

sub result ($self, $result = undef) {
    $self->{result} = $result if $result;
    return $self->{result} || 'na';
}

sub start ($self) {
    $self->{running} = 1;
    autotest::set_current_test($self);
}

sub done ($self) {
    $self->{running} = 0;
    $self->{result} ||= 'ok';
    unless ($self->{test_count}) {
        $self->take_screenshot();
    }
    autotest::set_current_test(undef);
}

sub fail_if_running ($self) {
    $self->{result} = 'fail' if $self->{result};
    autotest::set_current_test(undef);
}

sub skip_if_not_running ($self) {
    $self->{result} = 'skip' if !$self->{result};
    autotest::set_current_test(undef);
}


sub timeout_screenshot ($self) {
    my $n = ++$self->{timeoutcounter};
    $self->take_screenshot(sprintf("timeout-%02i", $n));
}

sub pre_run_hook ($self) {
    # you should overload that in test classes
    return;
}

sub post_run_hook ($self) {
    # you should overload that in test classes
    return;
}

sub run_post_fail ($self, $msg) {
    unless ($bmwqemu::vars{_SKIP_POST_FAIL_HOOKS}) {
        $self->{post_fail_hook_running} = 1;
        eval { $self->post_fail_hook; };
        bmwqemu::diag("post_fail_hook failed: $@") if $@;
        $self->{post_fail_hook_running} = 0;
    }
    $self->fail_if_running();
    die $msg . "\n";
}

sub execution_time { time - shift }

sub runtest ($self) {
    my $starttime = time;

    my $died;
    my $name = $self->{name};
    # Set flags to the field value
    $self->{flags} = $self->test_flags();
    eval {
        $self->pre_run_hook();
        if (defined $self->{run_args}) {
            $self->run($self->{run_args});
        }
        else {
            $self->run();
        }
        $self->post_run_hook();
    };
    if ($@) {
        # copy the exception early
        my $internal = Exception::Class->caught('OpenQA::Exception::InternalException');

        $self->{result} = 'fail';
        # add a fail screenshot in case there is none
        if (!@{$self->{details}} || ($self->{details}->[-1]->{result} || '') ne 'fail') {
            $self->take_screenshot();
        }
        # show a text result with the die message unless the die was internally generated
        if (!$internal) {
            my $msg = "# Test died: $@";
            bmwqemu::fctinfo($msg);
            $self->record_resultfile('Failed', $msg, result => 'fail');
            $died = 1;
        }
    }

    eval { $self->search_for_expected_serial_failures(); };
    # Process serial detection failure
    if ($@) {
        bmwqemu::diag($@);
        $self->record_resultfile('Failed', $@, result => 'fail');
        $died = 1;
    }

    $self->run_post_fail("test $name died") if ($died);

    if (($self->{result} || '') eq 'fail') {
        # fatal
        $self->run_post_fail("test $name failed");
    }

    $self->done();
    $self->{execution_time} = execution_time($starttime);
    bmwqemu::diag(sprintf("||| finished %s %s at %s (%d s)", $name, $self->{category}, POSIX::strftime('%F %T', gmtime), $self->{execution_time}));
    return;
}

sub save_test_result ($self) {
    my $result = {
        details        => $self->details(),
        result         => $self->result(),
        dents          => $self->{dents},
        execution_time => $self->{execution_time},
    };
    $result->{extra_test_results} = $self->{extra_test_results} if $self->{extra_test_results};

    # be aware that $name has to be unique within one job (also assumed in several other places)
    my $fn = bmwqemu::result_dir() . sprintf("/result-%s.json", $self->{name});
    bmwqemu::save_json_file($result, $fn);
    return $result;
}

sub next_resultname ($self, $type, $name) {
    my $testname = $self->{name};
    my $count    = ++$self->{test_count};
    if ($name) {
        return "$testname-$count.$name.$type";
    }
    else {
        return "$testname-$count.$type";
    }
}

sub write_resultfile ($self, $filename, $output) {
    path(bmwqemu::result_dir(), $filename)->spurt($output);
}

=head2 record_resultfile

    $self->record_resultfile($title, $output [, result => $result] [, resultname => $name]);

Record result file to be parsed when evaluating test results, for example
within the openQA web interface.
=cut
sub record_resultfile ($self, $title, $output, %nargs) {
    my $filename = $self->next_resultname('txt', $nargs{resultname});
    my $detail   = {
        title  => $title,
        result => $nargs{result},
        text   => $filename,
    };
    push @{$self->{details}}, $detail;
    $self->write_resultfile($filename, $output);
}

sub record_serialresult ($self, $ref, $res, $string = '') {
    # take screenshot for documentation (screenshot does not represent fail itself)
    $self->take_screenshot() unless (testapi::is_serial_terminal);

    my $output = "# wait_serial expected: $ref\n";
    $output .= "# Result:\n";
    $output .= "$string\n";
    $self->record_resultfile('wait_serial', $output, result => $res);
    return undef;
}

sub record_soft_failure_result ($self, $reason = '(no reason specified)', %args = undef) {
    my $result   = $self->record_testresult('softfail', %args);
    my $filename = $self->next_resultname('txt');
    $result->{title} = 'Soft Failed';
    $result->{text}  = $filename;
    $self->write_resultfile($filename, "# Soft Failure:\n$reason\n");
    $self->{dents}++;
    return undef;
}

sub register_extra_test_results ($self, $tests) {
    $self->{extra_test_results} //= [];
    foreach my $t (@{$tests}) {
        $t->{script} = $self->{script} if (!defined($t->{script}) || $t->{script} eq 'unk');
        push @{$self->{extra_test_results}}, $t;
    }
    return undef;
}

=head2 record_testresult

Makes a new test detail with the specified $result, adds it to the
test details and returns it.

=cut

sub record_testresult ($self, $result = 'unk', %args = undef) {
    # assign result as overall result unless it is already worse
    my $current_result = \$self->{result};
    if ($result eq 'fail') {
        $$current_result = 'fail';
    }
    elsif ($result eq 'softfail') {
        if (!$$current_result || $$current_result ne 'fail' || $args{force_status}) {
            $$current_result = 'softfail';
        }
    }
    elsif ($result && $result eq 'ok') {
        $$current_result //= 'ok';
    }
    else {
        # set $result to 'unk' if an invalid value has been specified
        $result = 'unk';
    }

    # add detail
    my $detail = {result => $result};
    push(@{$self->{details}}, $detail);
    ++$self->{test_count};
    return $detail;
}

=head2 _result_add_screenshot

internal function to add a screenshot to an existing result structure

=cut

sub _result_add_screenshot ($self, $result) {
    my $rsp = autotest::query_isotovideo('backend_last_screenshot_data');
    my $img = $rsp->{image};
    return $result unless $img;

    $img = tinycv::from_ppm(decode_base64($img));
    return $result unless $img;

    $result->{screenshot} = $self->next_resultname('png');
    $result->{frametime}  = _framenumber_to_timerange($rsp->{frame});

    my $fn = join('/', bmwqemu::result_dir(), $result->{screenshot});
    $img->write_with_thumbnail($fn);

    return $result;
}

=head2 take_screenshot

add screenshot with 'unk' result if an image is available

=cut

sub take_screenshot ($self, $res = 'unk') {
    my $result = $self->record_testresult($res);
    $self->_result_add_screenshot($result);

    # prevent adding incomplete result to details in case not image was available
    $self->remove_last_result() unless ($result->{screenshot});

    return $result;
}

sub capture_filename ($self) {
    my $fn = $self->{name} . "-captured.wav";
    die "audio capture already in progress. Stop it first!\n" if ($self->{wav_fn});
    $self->{wav_fn} = $fn;
    return $fn;
}

sub stop_audiocapture ($self) {
    bmwqemu::log_call();
    autotest::query_isotovideo('backend_stop_audiocapture');

    my $result = {
        audio  => $self->{wav_fn},
        result => 'unk',
    };

    push @{$self->{details}}, $result;

    return $result;
}

sub verify_sound_image ($self, $imgpath, $mustmatch, $check) {
    my $rsp = autotest::query_isotovideo('backend_verify_image', {imgpath => $imgpath, mustmatch => $mustmatch});

    my $img = tinycv::read($imgpath);
    if ($rsp->{found}) {
        my $foundneedle = $rsp->{found};
        $self->record_screenmatch($img, $foundneedle, [$mustmatch], $rsp->{candidates});
        my $lastarea = $foundneedle->{area}->[-1];
        bmwqemu::fctres(sprintf("found %s, similarity %.2f @ %d/%d", $foundneedle->{needle}->{name}, $lastarea->{similarity}, $lastarea->{x}, $lastarea->{y}));
        return $foundneedle;
    }
    bmwqemu::fctres(sprintf("failed to find %s", $mustmatch));
    my @needles_params = (img => $img, needles => $rsp->{candidates}, tags => [$mustmatch]);
    if ($check) {
        $self->record_screenfail(@needles_params, result => 'unk');
    }
    else {
        $self->record_screenfail(@needles_params, result => 'fail', overall => 'fail');
    }
    return;
}

=head2 ocr_checklist

Optical Character Recognition matching.

Return a listref containing hashrefs like this:

  {
    screenshot=>2,      # nr of screenshot for the test to OCR
    x=>104, y=>201,     # position
    xs=>380, ys=>150,   # size
    pattern=>"H ?ello", # regex to match the OCR result
    result=>"OK"        # or "fail"
  }

=cut

sub ocr_checklist {
    return [];
}

sub standstill_detected ($self, $lastscreenshot) {
    $self->record_screenfail(
        img     => $lastscreenshot,
        result  => 'fail',
        overall => 'fail'
    );

    testapi::send_key('alt-sysrq-w');
    testapi::send_key('alt-sysrq-l');
    testapi::send_key('alt-sysrq-d');    # only available with CONFIG_LOCKDEP
    return;
}

# this is called if the test failed and the framework loaded a VM
# snapshot - all consoles activated in the test's run function loose their
# state
sub rollback_activated_consoles ($self) {
    for my $console (@{$self->{activated_consoles}}) {
        # the backend will only reset its state, and call activate
        # the next time - the console itself might actually not be
        # able to activate a 2nd time, but that's up to the console class
        autotest::query_isotovideo('backend_reset_console', {testapi_console => $console});
    }
    $self->{activated_consoles} = [];

    if (defined($autotest::last_milestone_console)) {
        my $ret = autotest::query_isotovideo('backend_select_console',
            {testapi_console => $autotest::last_milestone_console});
        die $ret->{error} if $ret->{error};
    }

    return;
}

sub search_for_expected_serial_failures ($self) {
    if (defined $bmwqemu::vars{BACKEND} && $bmwqemu::vars{BACKEND} eq 'qemu') {
        $self->parse_serial_output_qemu();
    }
}

sub get_serial_output_json ($self) {
    myjsonrpc::send_json($autotest::isotovideo, {cmd => 'read_serial', position => $serial_file_pos});
    return myjsonrpc::read_json($autotest::isotovideo);
}

sub parse_serial_output_qemu ($self) {
    # serial failures defined in distri (test can override them)
    my $failures = $self->{serial_failures};

    my $json = $self->get_serial_output_json($serial_file_pos);
    my $die  = 0;
    my %regexp_matched;
    # loop line by line
    for my $line (split(/^/, $json->{serial})) {
        chomp $line;
        for my $regexp_table (@{$failures}) {
            my $regexp  = $regexp_table->{pattern};
            my $message = $regexp_table->{message};
            my $type    = $regexp_table->{type};

            # Input parameters validation
            die "Wrong type defined for serial failure. Only 'info', 'soft', 'hard' or 'fatal' allowed. Got: $type" if $type !~ /^info|soft|hard|fatal$/;
            die "Message not defined for serial failure for the pattern: '$regexp', type: $type"                    if !defined $message;

            # If you want to match a simple string please be sure that you create it with quotemeta
            if (!exists $regexp_matched{$regexp} and $line =~ /$regexp/) {
                $regexp_matched{$regexp} = 1;
                my $fail_type = 'softfail';
                if ($type eq 'info') {
                    $fail_type = 'ok';
                }
                elsif ($type =~ 'hard|fatal') {
                    $die                   = 1;
                    $fail_type             = 'fail';
                    $self->{fatal_failure} = $type eq 'fatal';
                }
                $self->record_resultfile($message, $message . " - Serial error: $line", result => $fail_type);
                $self->{result} = $fail_type;
            }
        }
    }
    $serial_file_pos = $json->{position};
    die "Got serial hard failure" if $die;
    return;
}

1;
