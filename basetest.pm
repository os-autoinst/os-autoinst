package basetest;
use strict;
use warnings;
use bmwqemu ();
use ocr;
use Time::HiRes;
use JSON;
use POSIX;
use testapi ();

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

    return bless $self, $class;
}

=head1 Methods

=head2 run

Body of the test to be implemented by child classes.
This code is run during test.

=head2 is_applicable

Return false if the test should be skipped.

Can eg. check vars{BIGTEST}, vars{LIVETEST}

=cut

sub is_applicable {
    return 1;
}

=head2 test_flags

Return a hash of flags that are either there or not

  without anything - rollback to 'lastgood' snapshot if failed
  'fatal' - whole test suite is in danger if this fails
  'milestone' - after this test succeeds, update 'lastgood'
  'important' - if this fails, set the overall state to 'fail'

default is obviously no flags, installation tests are 'fatal' by default

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

    my $count    = ++$self->{test_count};
    my $testname = ref($self);

    my $h          = $self->_serialize_match($match);
    my $properties = $match->{needle}->{properties} || [];
    my $result     = {
        needle     => $h->{name},
        area       => $h->{area},
        tags       => [@$tags],                                  # make a copy
        screenshot => sprintf("%s-%d.png", $testname, $count),
        result     => 'ok',
        properties => [@$properties],
    };

    # When the needle has the workaround property,
    # mark the result as dent and increase the dents
    if ($match->{needle}->has_property('workaround')) {
        $result->{dent} = 1;
        $self->{dents}++;
        bmwqemu::diag "needle '$h->{name}' is a workaround";
    }

    # Hack to make it obvious that some test passed by applying a hack
    # (such as clicking away some error popup). Those hacks are indicated by a
    # needle containing "bnc" in its name
    if ($h->{name} =~ /bnc\d{4}/) {
        $result->{dent} = 1;
        $self->{dents}++;
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
    my $count    = $self->{"test_count"};

    my $candidates;
    my $diffcount = 0;

    my $name = $cand->{needle}->{name};

    my $h = {name => $name, error => $cand->{error}, area => []};
    for my $a (@{$cand->{area}}) {
        my $na = {};
        for my $i (qw/x y w h result/) {
            $na->{$i} = $a->{$i};
        }
        $na->{similarity} = int($a->{similarity} * 100);
        if ($a->{diff}) {
            my $imgname = sprintf("%s-%d-%s-diff%d.png", $testname, $count, $name, $diffcount++);
            $a->{diff}->write(join('/', bmwqemu::result_dir(), $imgname));
            $na->{diff} = $imgname;
        }
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

    my $count    = ++$self->{"test_count"};
    my $testname = ref($self);

    my $candidates;
    for my $cand (@{$needles || []}) {
        push @$candidates, $self->_serialize_match($cand);
    }

    my $result = {
        screenshot => sprintf("%s-%d.png", $testname, $count),
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
    $bmwqemu::backend->set_serial_offset();
    autotest::set_current_test($self);
}

sub done() {
    my $self = shift;
    $self->{running} = 0;
    $self->{result} ||= 'ok';
    unless ($self->{"test_count"}) {
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

sub waitforprevimg {
    my ($self, $previmg, $timeout) = @_;
    $timeout ||= 5;

    my $name = ref($self);
    my $currentimg;

    for (my $i = 0; $i <= $timeout; $i += 1) {
        $currentimg = bmwqemu::getcurrentscreenshot();
        my $sim = $currentimg->similarity($previmg);
        bmwqemu::diag "$i: SIM $name $sim";
        if ($sim >= 49) {
            return;
        }
        sleep 1;
    }
    return $currentimg;
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
    if ($@ || ($self->{result} || '') eq 'fail') {
        my $msg = "test $name " . ($@ ? 'died: ' . $@ : 'failed');
        warn $msg;
        # add a fail screenshot in case there is none
        if ($@ && (!@{$self->{details}} || ($self->{details}->[-1]->{result} || '') ne 'fail')) {
            my $result = $self->record_testresult('fail');
            $self->_result_add_screenshot($result);
        }
        $self->{post_fail_hook_running} = 1;
        eval { $self->post_fail_hook; };
        bmwqemu::diag "post_fail_hook failed: $@\n" if $@;
        $self->{post_fail_hook_running} = 0;
        $self->fail_if_running();
        die $msg . "\n";
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
    my $count    = ++$self->{"test_count"};
    if ($name) {
        return "$testname-$count.$name.$type";
    }
    else {
        return "$testname-$count.$type";
    }
}

sub record_serialresult {
    my ($self, $ref, $res) = @_;

    my $result = $self->record_testresult($res);
    $self->_result_add_screenshot($result);

    $result->{reference_text} = $ref;

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
    ++$self->{"test_count"};

    return $result;
}

=head2 _result_add_screenshot

internal function to add a screenshot to an existing result structure

=cut

sub _result_add_screenshot {
    my ($self, $result, $img) = @_;

    $img //= bmwqemu::getcurrentscreenshot();

    my $count    = $self->{"test_count"};
    my $testname = ref($self);

    $result->{screenshot} = sprintf("%s-%d.png", $testname, $count);

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

sub start_audiocapture {
    my ($self) = @_;
    my $fn = ref($self) . "-captured.wav";
    die "audio capture already in progress. Stop it first!\n" if ($self->{wav_fn});

    $self->{wav_fn} = $fn;
    my $filename = join('/', bmwqemu::result_dir(), 'ulogs', $fn);
    bmwqemu::log_call('start_audiocapture', filename => $filename);
    return $bmwqemu::backend->start_audiocapture({filename => $filename});
}

sub stop_audiocapture {
    my ($self) = @_;

    bmwqemu::log_call('stop_audiocapture');
    $bmwqemu::backend->stop_audiocapture;

    my $result = {
        audio  => $self->{wav_fn},
        result => 'unk',
    };

    push @{$self->{details}}, $result;

    return $result;
}

sub assert_recorded_sound {
    my ($self, $mustmatch) = @_;

    my $result = $self->stop_audiocapture();
    my $wavfile = join('/', bmwqemu::result_dir(), 'ulogs', $result->{audio});
    # qemuscreenshots has always been a bad name, it just got worse ;/
    system("/suse/coolo/prod/os-autoinst/snd2png/snd2png $wavfile $result->{audio}.png");

    my $needles = needle::tags($mustmatch) || [];

    my $img = tinycv::read("$result->{audio}.png");
    my ($foundneedle, $failed_candidates) = $img->search($needles, 0, 1);
    if ($foundneedle) {
        $self->record_screenmatch($img, $foundneedle, [$mustmatch], $failed_candidates);
        my $lastarea = $foundneedle->{area}->[-1];
        bmwqemu::fctres(sprintf("found %s, similarity %.2f @ %d/%d", $foundneedle->{needle}->{name}, $lastarea->{similarity}, $lastarea->{x}, $lastarea->{y}));
        return $foundneedle;
    }
    bmwqemu::fctres(sprintf("failed to find %s", $mustmatch));

    $self->record_screenfail(
        img     => $img,
        needles => $failed_candidates,
        tags    => [$mustmatch],
        result  => $result,
        overall => 'fail'
    );
    return;
}

=head2 ocr_checklist

Optical Character Recognition matching.

Return a listref containing hashrefs like this:

  {
    screenshot=>2,		# nr of screenshot for the test to OCR
    x=>104, y=>201,		# position
    xs=>380, ys=>150,		# size
    pattern=>"H ?ello",		# regex to match the OCR result

    result=>"OK"		# or "fail"
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

1;

# vim: set sw=4 et:
