# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2015 SUSE LLC
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
use strict;
use warnings;
use autodie ':all';
use bmwqemu ();
use ocr;
use Time::HiRes;
use JSON;
use POSIX;
use testapi  ();
use autotest ();
use MIME::Base64 'decode_base64';

# enable strictures and warnings in all tests globaly
sub import {
    strict->import;
    warnings->import;
}

sub new {
    my ($class, $category) = @_;
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

    return bless $self, $class;
}

=head1 Methods

=head2 run

Body of the test to be implemented by child classes.
This code is run during test.

=head2 is_applicable

Return false if the test should be skipped.

By default it check the test name and fullname against comma-separated
blacklist in EXCLUDE_MODULES variable and returns false if it is found there.

Can eg. check vars{BIGTEST}, vars{LIVETEST}

=cut

sub is_applicable {
    my ($self) = @_;
    if ($bmwqemu::vars{EXCLUDE_MODULES}) {
        my %excluded = map { $_ => 1 } split(/\s*,\s*/, $bmwqemu::vars{EXCLUDE_MODULES});

        return 0 if $excluded{$self->{class}};
        return 0 if $excluded{$self->{fullname}};
    }

    return 1;
}

=head2 test_flags

Return a hash of flags that are either there or not

  'fatal'          - abort whole test suite if this fails (and set overall state 'failed')
  'ignore_failure' - if this module fails, it will not affect the overall result at all
  'milestone'      - after this test succeeds, update 'lastgood'
  'norollback'     - don't roll back to 'lastgood' snapshot if this fails

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

sub record_screenmatch {
    my ($self, $img, $match, $tags, $failed_needles) = @_;
    $tags           ||= [];
    $failed_needles ||= [];

    my $h          = $self->_serialize_match($match);
    my $properties = $match->{needle}->{properties} || [];
    my $result     = {
        needle     => $h->{name},
        area       => $h->{area},
        tags       => [@$tags],                        # make a copy
        screenshot => $self->next_resultname('png'),
        result     => 'ok',
        properties => [@$properties],
        json       => $h->{json},
    };

    # make sure needle is blessed
    my $foundneedle = bless $match->{needle}, "needle";

    # When the needle has the workaround property,
    # mark the result as dent and increase the dents
    if ($foundneedle->has_property('workaround')) {
        $result->{dent} = 1;
        $self->{dents}++;
        bmwqemu::diag("needle '$h->{name}' is a workaround");
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

sub _serialize_match {
    my ($self, $cand) = @_;

    my $testname = ref($self);
    my $count    = $self->{test_count};

    my $candidates;
    my $diffcount = 0;

    my $name     = $cand->{needle}->{name};
    my $jsonfile = $cand->{needle}->{file};

    my $h = {name => $name, error => $cand->{error}, area => [], json => $jsonfile};
    for my $a (@{$cand->{area}}) {
        my $na = {};
        for my $i (qw(x y w h result)) {
            $na->{$i} = $a->{$i};
        }
        $na->{similarity} = int($a->{similarity} * 100);
        push @{$h->{area}}, $na;
    }

    return $h;
}

sub record_screenfail {
    my $self    = shift;
    my %args    = @_;
    my $img     = $args{img};
    my $needles = $args{needles} || [];
    my $tags    = $args{tags} || [];
    my $status  = $args{result} || 'fail';
    my $overall = $args{overall};            # whether and how to set global test result

    my $candidates;
    for my $cand (@{$needles || []}) {
        push @$candidates, $self->_serialize_match($cand);
    }

    my $result = {
        screenshot => $self->next_resultname('png'),
        result     => $status,
    };

    $result->{needles} = $candidates if $candidates;
    $result->{tags}    = [@$tags]    if $tags;         # make a copy

    my $fn = join('/', bmwqemu::result_dir(), $result->{screenshot});
    $img->write_with_thumbnail($fn);

    $self->{result} = $overall if $overall;

    push @{$self->{details}}, $result;
    return $result;
}

# for interactive mode
sub remove_last_result {
    my $self = shift;
    --$self->{test_count};
    return pop @{$self->{details}};
}

sub details {
    my ($self) = @_;
    return $self->{details};
}

sub result {
    my ($self, $result) = @_;
    $self->{result} = $result if $result;
    return $self->{result} || 'na';
}

sub start() {
    my ($self) = @_;
    $self->{running} = 1;
    autotest::set_current_test($self);
}

sub done() {
    my $self = shift;
    $self->{running} = 0;
    $self->{result} ||= 'ok';
    unless ($self->{test_count}) {
        $self->take_screenshot();
    }
    autotest::set_current_test(undef);
}

sub fail_if_running() {
    my $self = shift;
    $self->{result} = 'fail' if $self->{result};
    autotest::set_current_test(undef);
}

sub skip_if_not_running() {
    my ($self) = @_;

    $self->{result} = 'skip' if !$self->{result};
    autotest::set_current_test(undef);
}


sub timeout_screenshot() {
    my ($self) = @_;

    my $n = ++$self->{timeoutcounter};
    $self->take_screenshot(sprintf("timeout-%02i", $n));
}

sub pre_run_hook {
    my ($self) = @_;

    # you should overload that in test classes
    return;
}

sub post_run_hook {
    my ($self) = @_;

    # you should overload that in test classes
    return;
}

sub run_post_fail {
    my ($self, $msg) = @_;
    $self->{post_fail_hook_running} = 1;
    eval { $self->post_fail_hook; };
    bmwqemu::diag("post_fail_hook failed: $@") if $@;
    $self->{post_fail_hook_running} = 0;
    $self->fail_if_running();
    die $msg . "\n";
}

sub runtest {
    my ($self) = @_;
    my $starttime = time;

    my $ret;
    my $name = ref($self);
    eval {
        $self->pre_run_hook();
        $self->run();
        $self->post_run_hook();
    };
    if ($@) {
        # copy the exception early
        my $internal = Exception::Class->caught('OpenQA::Exception::InternalException');

        $self->{result} = 'fail';
        # add a fail screenshot in case there is none
        if (!@{$self->{details}} || ($self->{details}->[-1]->{result} || '') ne 'fail') {
            my $result = $self->record_testresult('unk');
            $self->_result_add_screenshot($result);
        }
        # show a text result with the die message unless the die was internally generated
        if (!$internal) {
            my $msg = "# Test died: $@";
            bmwqemu::diag($msg);
            my $details = {result => 'fail'};
            my $text_fn = $self->next_resultname('txt');
            open my $fd, ">", bmwqemu::result_dir() . "/$text_fn";
            print $fd $msg;
            close $fd;
            $details->{text}  = $text_fn;
            $details->{title} = 'Failed';
            push @{$self->{details}}, $details;
            $self->run_post_fail("test $name died");
        }
    }
    if (($self->{result} || '') eq 'fail') {
        # fatal
        $self->run_post_fail("test $name failed");
    }
    $self->done();
    bmwqemu::diag(sprintf("||| finished %s %s at %s (%d s)", $name, $self->{category}, POSIX::strftime('%F %T', gmtime), time - $starttime));
    return $ret;
}

sub save_test_result() {
    my ($self) = @_;

    my $result = {
        details => $self->details(),
        result  => $self->result(),
        dents   => $self->{dents},
    };
    $result->{extra_test_results} = $self->{extra_test_results} if $self->{extra_test_results};

    # be aware that $name has to be unique within one job (also assumed in several other places)
    my $fn = bmwqemu::result_dir() . sprintf("/result-%s.json", ref $self);
    bmwqemu::save_json_file($result, $fn);
    return $result;
}

sub next_resultname {
    my ($self, $type, $name) = @_;
    my $testname = ref($self);
    my $count    = ++$self->{test_count};
    if ($name) {
        return "$testname-$count.$name.$type";
    }
    else {
        return "$testname-$count.$type";
    }
}

=head2 record_resultfile

    $self->record_resultfile($title, $output [, result => $result] [, resultname => $name]);

Record result file to be parsed when evaluating test results, for example
within the openQA web interface.
=cut
sub record_resultfile {
    my ($self, $title, $output, %nargs) = @_;
    my $filename = $self->next_resultname('txt', $nargs{resultname});
    my $detail = {
        title  => $title,
        result => $nargs{result},
        text   => $filename,
    };
    push @{$self->{details}}, $detail;
    open my $fh, '>', bmwqemu::result_dir() . "/$filename";
    print $fh $output;
    close $fh;
}

sub record_serialresult {
    my ($self, $ref, $res, $string) = @_;

    $string //= '';

    my $result = $self->record_testresult('unk');
    unless (testapi::is_serial_terminal) {
        # the screenshot is not the fail, it's just for documentation
        $self->_result_add_screenshot($result);
    }
    my $output = "# wait_serial expected: $ref\n\n";
    $output .= "# Result:\n";
    $output .= "$string\n";
    $self->record_resultfile('wait_serial', $output, result => $res);
    return $result;
}

sub record_soft_failure_result {
    my ($self, $reason) = @_;
    $reason //= '(no reason specified)';

    my $result = $self->record_testresult('unk');
    $self->_result_add_screenshot($result);
    my $output = "# Soft Failure:\n$reason\n";
    $self->record_resultfile('Soft Failed', $output, result => $result);
    return $result;
}

sub register_extra_test_results {
    my ($self, $tests) = @_;

    $self->{extra_test_results} //= [];
    push @{$self->{extra_test_results}}, @$tests;
    return;
}

=head2 record_testresult

generic function that adds a test result to results and re-computes overall state

=cut

sub record_testresult {
    my ($self, $res) = @_;

    unless ($res && $res =~ /(ok|unk|fail)/) {
        $res = 'unk';
    }

    if ($res eq 'fail') {
        $self->{result} = $res;
    }
    elsif ($res eq 'ok') {
        $self->{result} ||= $res;
    }

    my $result = {result => $res,};

    push @{$self->{details}}, $result;
    ++$self->{test_count};

    return $result;
}

=head2 _result_add_screenshot

internal function to add a screenshot to an existing result structure

=cut

sub _result_add_screenshot {
    my ($self, $result) = @_;

    my $img = autotest::query_isotovideo('backend_last_screenshot_data')->{image};
    return $result unless $img;

    $img = tinycv::from_ppm(decode_base64($img));
    return $result unless $img;

    $result->{screenshot} = $self->next_resultname('png');

    my $fn = join('/', bmwqemu::result_dir(), $result->{screenshot});
    $img->write_with_thumbnail($fn);

    return $result;
}

=head2 take_screenshot

add screenshot with 'unk' result

=cut

sub take_screenshot {
    my ($self, $res) = @_;
    $res ||= 'unk';

    my $result = $self->record_testresult($res);
    $self->_result_add_screenshot($result);

    return $result;
}

sub capture_filename {
    my ($self) = @_;
    my $fn = ref($self) . "-captured.wav";
    die "audio capture already in progress. Stop it first!\n" if ($self->{wav_fn});
    $self->{wav_fn} = $fn;
    return $fn;
}

sub stop_audiocapture {
    my ($self) = @_;

    bmwqemu::log_call();
    autotest::query_isotovideo('backend_stop_audiocapture');

    my $result = {
        audio  => $self->{wav_fn},
        result => 'unk',
    };

    push @{$self->{details}}, $result;

    return $result;
}

sub verify_sound_image {
    my ($self, $imgpath, $mustmatch) = @_;

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

    $self->record_screenfail(
        img     => $img,
        needles => $rsp->{candidates},
        tags    => [$mustmatch],
        result  => 'fail',
        overall => 'fail'
    );
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

sub standstill_detected {
    my ($self, $lastscreenshot) = @_;

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
sub rollback_activated_consoles {
    my ($self) = @_;
    for my $console (@{$self->{activated_consoles}}) {
        # the backend will only reset its state, and call activate
        # the next time - the console itself might actually not be
        # able to activate a 2nd time, but that's up to the console class
        autotest::query_isotovideo('backend_reset_console', {testapi_console => $console});
    }
    return;
}

1;

# vim: set sw=4 et:
