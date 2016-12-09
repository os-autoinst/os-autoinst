# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2016 SUSE LLC
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

# this is an abstract class
package backend::baseclass;
use strict;
use warnings;
use Carp qw(cluck carp confess);
use JSON 'to_json';
use File::Copy 'cp';
use File::Basename;
use Time::HiRes qw(gettimeofday tv_interval);
use POSIX '_exit';
use bmwqemu;
use IO::Select;
require IPC::System::Simple;
use autodie ':all';
use myjsonrpc;

use Net::SSH2;
use feature 'say';

my $framecounter = 0;    # screenshot counter

# should be a singleton - and only useful in backend process
our $backend;

use parent 'Class::Accessor::Fast';
__PACKAGE__->mk_accessors(
    qw(
      update_request_interval last_update_request screenshot_interval
      last_screenshot _last_screenshot_name last_image
      reference_screenshot assert_screen_tags assert_screen_needles assert_screen_deadline
      assert_screen_fails assert_screen_last_check stall_detected
      reload_needles
      ));

sub new {
    my $class = shift;
    my $self = bless({class => $class}, $class);
    $self->{started}       = 0;
    $self->{serialfile}    = "serial0";
    $self->{serial_offset} = 0;
    return $self;
}

# runs in the backend process to deserialize VNC commands
sub handle_command {
    my ($self, $cmd) = @_;

    my $func = $cmd->{cmd};
    unless ($self->can($func)) {
        die "not supported command: $func";
    }
    return $self->$func($cmd->{arguments});
}

sub die_handler {
    my $msg = shift;
    cluck "DIE $msg\n";
    $backend->stop_vm();
    $backend->close_pipes();
}

sub backend_signalhandler {
    my ($sig) = @_;
    bmwqemu::diag("backend got $sig");
    $backend->stop_vm;
}

sub run {
    my ($self, $cmdpipe, $rsppipe) = @_;

    die "there can be only one!" if $backend;
    $backend = $self;

    $SIG{__DIE__} = \&die_handler;
    $SIG{TERM}    = \&backend_signalhandler;

    my $io = IO::Handle->new();
    $io->fdopen($cmdpipe, "r") || die "r fdopen $!";
    $self->{cmdpipe} = $io;

    $io = IO::Handle->new();
    $io->fdopen($rsppipe, "w") || die "w fdopen $!";
    $rsppipe = $io;
    $io->autoflush(1);
    $self->{rsppipe} = $io;

    printf STDERR "$$: cmdpipe %d, rsppipe %d\n", fileno($self->{cmdpipe}), fileno($self->{rsppipe});

    bmwqemu::diag "started mgmt loop with pid $$";

    $self->{select} = IO::Select->new();
    $self->{select}->add($self->{cmdpipe});

    $self->last_update_request("-Inf" + 0);
    $self->last_screenshot(undef);
    $self->screenshot_interval($bmwqemu::vars{SCREENSHOTINTERVAL} || .5);
    $self->update_request_interval($self->screenshot_interval());

    for my $console (values %{$testapi::distri->{consoles}}) {
        # tell the consoles who they need to talk to (in this thread)
        $console->backend($self);
    }

    $self->run_capture_loop($self->{select});

    bmwqemu::diag("management process exit at " . POSIX::strftime("%F %T", gmtime));
}

use List::Util 'min';

=head2 run_capture_loop(\@select, $timeout, $update_request_interval, $screenshot_interval)

=out

=item select

IO::Select object that is polled when given

=item timeout

run the loop this long in seconds, indefinitely if undef, or until the
$self->{cmdpipe} is closed, whichever occurs first.

=item update_request_interval

space out update polls for this interval in seconds, i.e. update the
internal buffers this often.

If unset, use $self->{update_request_interval}.  For the main capture
loop $self->{update_request_interval} can be modified while this loop
is running, e.g. to poll more often for a stretch of time.

=item screenshot_interval

space out screen captures for this interval in seconds, i.e. save a
screenshot from the buffers this often.

If unset, use $self->{screenshot_interval}.  For the main capture
loop, $self->{screenshot_interval} can be modified while this loop is
running, e.g. to do some fast or slow motion.

=back

=cut

sub run_capture_loop {
    my ($self, $select, $timeout, $update_request_interval, $screenshot_interval) = @_;
    my $starttime = gettimeofday;

    if (!$self->last_screenshot) {
        my $now = gettimeofday;
        $self->last_screenshot($now);
    }

    eval {
        while (1) {

            last if (!$self->{cmdpipe});

            my $now = gettimeofday;

            my $time_to_timeout = "Inf" + 0;
            if (defined $timeout) {
                $time_to_timeout = $timeout - ($now - $starttime);

                last if $time_to_timeout <= 0;
            }

            my $time_to_update_request = ($update_request_interval // $self->update_request_interval) - ($now - $self->last_update_request);
            if ($time_to_update_request <= 0) {
                $self->request_screen_update();
                $self->last_update_request($now);
                $time_to_update_request = ($update_request_interval // $self->update_request_interval);
            }

            # if we got stalled for a long time, we assume bad hardware and report it
            if ($self->assert_screen_last_check && $now - $self->last_screenshot > $self->screenshot_interval * 20) {
                $self->stall_detected(1);
                bmwqemu::diag sprintf("WARNING: There is some problem with your environment, we detected a stall for %d seconds", $now - $self->last_screenshot);
            }

            my $time_to_screenshot = ($screenshot_interval // $self->screenshot_interval) - ($now - $self->last_screenshot);
            if ($time_to_screenshot <= 0) {
                $self->capture_screenshot();
                $self->last_screenshot($now);
                $time_to_screenshot = ($screenshot_interval // $self->screenshot_interval);
            }

            my $time_to_next = min($time_to_screenshot, $time_to_update_request, $time_to_timeout);
            if (defined $select) {
                my ($read_set, $write_set) = IO::Select->select($select, $select, undef, $time_to_next);
                for my $fh (@$read_set) {
                    unless ($self->check_socket($fh, 0)) {
                        die "huh! $fh\n";
                    }
                    # don't check for further sockets after this one as
                    # check_socket can have side effects on the sockets
                    # (e.g. console resets), so better take the next socket
                    # next time
                    $write_set = [];
                    last;
                }
                for my $fh (@$write_set) {
                    unless ($self->check_socket($fh, 1)) {
                        die "huh! $fh\n";
                    }
                    last;
                }
            }
            else {
                sleep($time_to_next);
            }
        }
    };

    if ($@) {
        bmwqemu::diag "capture loop failed $@";
        $self->close_pipes();
    }
    return;
}

sub write_encoder_frame {
    my ($self, $frame) = @_;

    open(my $fh, '>>', 'video.log');
    print $fh "$frame\n";
    close($fh);
}

sub start_encoder {
    my ($self) = @_;

    $self->{encoder_pid} = 0;
    return if $bmwqemu::vars{NOVIDEO};

    # create empty file
    open(my $fh, '>', 'video.log');
    close($fh);
    my $cwd = Cwd::getcwd();
    $self->{encoder_pid} = fork();
    if (!$self->{encoder_pid}) {
        exec('nice', '-n', '19', "$bmwqemu::scriptdir/videoencoder", "$cwd/video.log", "$cwd/video.ogv");
    }
    return;
}

# new api

sub start_vm {
    my ($self) = @_;
    $self->{started} = 1;
    $self->start_encoder();
    return $self->do_start_vm();
}

sub stop_vm {
    my ($self) = @_;
    if ($self->{started}) {
        kill(TERM => $self->{encoder_pid}) if $self->{encoder_pid};
        # backend.run might have disappeared already in case of failed builds
        no autodie 'unlink';
        unlink('backend.run');
        $self->do_stop_vm();
        waitpid($self->{encoder_pid}, 0);
        $self->{started} = 0;
    }
    $self->close_pipes();    # does not return
    return;
}

sub alive {
    my ($self) = @_;
    if ($self->{started}) {
        if ($self->file_alive() and $self->raw_alive()) {
            return 1;
        }
        else {
            bmwqemu::diag("ALARM: backend.run got deleted! - exiting...");
            _exit(1);
        }
    }
    return 0;
}

my $iscrashedfile = 'backend.crashed';
sub unlink_crash_file {
    unlink($iscrashedfile) if -e $iscrashedfile;
}

sub write_crash_file {
    open(my $fh, ">", $iscrashedfile);
    print $fh "crashed\n";
    close $fh;
}

# new api end

# virtual methods
sub notimplemented() { confess "backend method not implemented" }

sub power {

    # parameters: acpi, reset, (on), off
    notimplemented;
}

sub insert_cd { notimplemented }
sub eject_cd  { notimplemented }

sub do_start_vm {
    # start up the vm
    notimplemented;
}

sub do_stop_vm { notimplemented }

sub stop { notimplemented }
sub cont { notimplemented }

sub can_handle {
    my ($self, $args) = @_;
    return;    # sorry, no
}

sub do_extract_assets { notimplemented }

sub is_shutdown {
    return -1;
}

sub save_memory_dump {
    notimplemented;
}

sub save_storage_drives {
    notimplemented;
}

## MAY be overwritten:

sub cpu_stat {
    # vm's would return
    # (userstat, systemstat)
    return [];
}

# helper function to make sure a screenshot is written
sub write_img {
    my ($self, $image, $filename) = @_;

    return if (!$image);

    if ($filename && !-f $filename) {
        $image->write($filename) || return;
    }
    return $filename;
}

sub enqueue_screenshot {
    my ($self, $image) = @_;

    return unless $image;

    my $starttime = gettimeofday;

    $image = $image->scale(1024, 768);

    $framecounter++;

    my $filename = $bmwqemu::screenshotpath . sprintf("/shot-%010d.png", $framecounter);
    my $lastlink = $bmwqemu::screenshotpath . "/last.png";

    my $lastscreenshot = $self->last_image;

    # link identical files to save space
    my $sim = 0;
    $sim = $lastscreenshot->similarity($image) if $lastscreenshot;

    my $mt1 = gettimeofday;

    # 54 is based on t/data/user-settings-*
    if ($sim <= 54) {
        # don't write a new screenshot by default not to waste cycles
        $self->write_img($image, $filename) || die "write $filename";
        $self->last_image($image);
        $self->_last_screenshot_name($filename);
        no autodie 'unlink';
        unlink($lastlink);
        symlink(basename($self->_last_screenshot_name), $lastlink);
    }

    if ($sim > 50) {    # we ignore smaller differences
        $self->write_encoder_frame('R');
    }
    else {
        my $name = $self->_last_screenshot_name;
        $self->write_encoder_frame("E $name");
    }
    my $d = gettimeofday - $starttime;
    if ($d > $self->screenshot_interval) {
        bmwqemu::diag sprintf("WARNING: enqueue_screenshot took %.2f seconds - slow IO? (opencv: %.2f - encoder: %.2f)", $d, $mt1 - $starttime, gettimeofday - $mt1);
    }
    return;
}

sub close_pipes {
    my ($self) = @_;

    if ($self->{cmdpipe}) {
        close($self->{cmdpipe}) || die "close $!\n";
        $self->{cmdpipe} = undef;
    }

    return unless $self->{rsppipe};

    bmwqemu::diag "sending magic and exit";
    $self->{rsppipe}->print('{"QUIT":1}');
    close($self->{rsppipe}) || die "close $!\n";
    _exit(0);
}

# this is called for all sockets ready to read from
sub check_socket {
    my ($self, $fh, $write) = @_;

    if ($self->{cmdpipe} && $fh == $self->{cmdpipe}) {
        return 1 if $write;
        my $cmd = myjsonrpc::read_json($self->{cmdpipe});

        if ($cmd->{cmd}) {
            my $rsp = {rsp => ($self->handle_command($cmd) // 0)};
            $rsp->{json_cmd_token} = $cmd->{json_cmd_token};
            if ($self->{rsppipe}) {    # the command might have closed it
                my $JSON = JSON->new()->convert_blessed();
                my $json = $JSON->encode($rsp);
                $self->{rsppipe}->print($json);
            }
        }
        else {
            use Data::Dumper;
            die "no command in " . Dumper($cmd);
        }
        return 1;
    }
    return 0;
}

###################################################################
## access other consoles from the test case process

# There can be two vnc backends (local Xvnc or remote vnc) and
# there can be several terminals on the local Xvnc.
#
# switching means: turn to the right vnc and if it's the Xvnc,
# iconify/deiconify the right x3270 terminal window.
#
# FIXME? for now, we just raise the terminal window to the front on
# the local-Xvnc DISPLAY.
#
# should we hide the other windows, somehow?
#if exists $self->{current_console} ...
# my $current_window_id = $self->{current_console}->{window_id};
# if (defined $current_window_id) {
#     system("DISPLAY=$display xdotool windowminimize --sync $current_window_id");
# }
#-> select

sub select_console {
    my ($self, $args) = @_;
    my $testapi_console = $args->{testapi_console};

    my $selected_console = $self->console($testapi_console);
    my $activated        = $selected_console->select;

    $self->{current_console} = $selected_console;
    $self->{current_screen}  = $selected_console->screen;
    $self->capture_screenshot();
    return {activated => $activated};
}

sub reset_consoles {
    my ($self, $args) = @_;

    # we iterate through all consoles
    for my $console (keys %{$testapi::distri->{consoles}}) {
        #next if ($console eq 'x3270');
        $self->reset_console({testapi_console => $console});
    }
    return;
}

sub reset_console {
    my ($self, $args) = @_;
    $self->console($args->{testapi_console})->reset;
    return;
}

sub deactivate_console {
    my ($self, $args) = @_;
    my $testapi_console = $args->{testapi_console};

    my $console_info = $self->console($testapi_console);
    if (defined $self->{current_console} && $self->{current_console} == $console_info) {
        $self->{current_console} = undef;
    }
    $console_info->disable();
    return;
}

sub request_screen_update {
    my ($self) = @_;

    return $self->bouncer('request_screen_update', undef);
}

sub console {
    my ($self, $testapi_console) = @_;

    my $ret = $testapi::distri->{consoles}->{$testapi_console};
    unless ($ret) {
        carp "console $testapi_console does not exist";
    }
    return $ret;
}

sub bouncer {
    my ($self, $call, $args) = @_;
    # forward to the current VNC console
    return unless $self->{current_screen};
    return $self->{current_screen}->$call($args);
}

sub send_key() {
    my ($self, $args) = @_;
    return $self->bouncer('send_key', $args);
}

sub hold_key() {
    my ($self, $args) = @_;
    return $self->bouncer('hold_key', $args);
}

sub release_key() {
    my ($self, $args) = @_;
    return $self->bouncer('release_key', $args);
}

sub type_string() {
    my ($self, $args) = @_;
    return $self->bouncer('type_string', $args);
}

sub mouse_set() {
    my ($self, $args) = @_;
    return $self->bouncer('mouse_set', $args);
}

sub mouse_hide() {
    my ($self, $args) = @_;
    return $self->bouncer('mouse_hide', $args);
}

sub mouse_button() {
    my ($self, $args) = @_;
    return $self->bouncer('mouse_button', $args);
}

sub get_last_mouse_set() {
    my ($self, $args) = @_;
    return $self->bouncer('get_last_mouse_set', $args);
}

sub is_serial_terminal {
    my ($self, $args) = @_;
    return {yesorno => $self->{current_console}->is_serial_terminal};
}

sub capture_screenshot {
    my ($self) = @_;
    return unless $self->{current_screen};

    my $screen = $self->{current_screen}->current_screen();
    $self->enqueue_screenshot($screen) if $screen;
    return;
}

###################################################################
# this is used by backend::console_proxy
sub proxy_console_call {
    my ($self, $wrapped_call) = @_;

    my ($console, $function, $args) = @$wrapped_call{qw(console function args)};
    $console = $self->console($console);

    my $wrapped_result = {};

    eval {
        # Do not die in here.
        # Move the decision to actually die to the server side instead.
        # For this ignore backend::baseclass::die_handler.
        local $SIG{__DIE__} = 'DEFAULT';
        $wrapped_result->{result} = $console->$function(@$args);
    };

    if ($@) {
        $wrapped_result->{exception} = join("\n", bmwqemu::pp($wrapped_call), $@);
    }

    return $wrapped_result;
}

=head2 set_serial_offset

Determines the starting offset within the serial file - so that we do not check the
previous test's serial output. Call this before you start doing something new

=cut

sub set_serial_offset {
    my ($self, $args) = @_;

    $self->{serial_offset} = -s $self->{serialfile};
    return $self->{serial_offset};
}


=head2 serial_text

Returns the output on the serial device since the last call to set_serial_offset

=cut

sub serial_text {
    my ($self) = @_;

    open(my $SERIAL, "<", $self->{serialfile});
    seek($SERIAL, $self->{serial_offset}, 0);
    local $/;
    my $data = <$SERIAL>;
    close($SERIAL);
    return $data;
}

sub wait_serial {
    my ($self, $args) = @_;

    my $regexp  = $args->{regexp};
    my $timeout = $args->{timeout};
    my $matched = 0;
    my $str;

    if ($self->{current_console}->is_serial_terminal) {
        return $self->{current_screen}->read_until($regexp, $timeout, %$args);
    }

    if (ref $regexp ne 'ARRAY') {
        $regexp = [$regexp];
    }

    my $initial_time = time;
    while (time < $initial_time + $timeout) {
        $str = $self->serial_text();
        for my $r (@$regexp) {
            if (ref $r eq 'Regexp') {
                $matched = $str =~ $r;
            }
            else {
                $matched = $str =~ m/$r/;
            }
            if ($matched) {
                $regexp = "$r";
                last;
            }
        }
        last if ($matched);
        # 1 second timeout, .19 froh's magic number :)
        $self->run_capture_loop($self->{select}, 1, .19);
    }
    $self->set_serial_offset();
    return {matched => $matched, string => $str};
}

# set_reference_screenshot and similiarity_to_reference are necessary to
# implement wait_still and wait_changed functions in the tests without having
# to transfer the screenshot into the test process
sub set_reference_screenshot {
    my ($self, $args) = @_;

    $self->reference_screenshot($self->last_image);
    return;
}

sub similiarity_to_reference {
    my ($self, $args) = @_;
    if (!$self->reference_screenshot || !$self->last_image) {
        return {sim => 10000};
    }
    return {sim => $self->reference_screenshot->similarity($self->last_image)};
}

sub wait_idle {
    my ($self, $args) = @_;
    my $timeout = $args->{timeout};

    bmwqemu::diag("wait_idle sleeping for $timeout seconds");
    $self->run_capture_loop($self->{select}, $timeout);
    return;
}

sub set_tags_to_assert {
    my ($self, $args) = @_;
    my $mustmatch     = $args->{mustmatch};
    my $timeout       = $args->{timeout} // $bmwqemu::default_timeout;
    my $reloadneedles = $args->{reloadneedles} || 0;

    # free all needle images
    for my $n (needle->all()) {
        $n->{img} = undef;
    }

    # get the array reference to all matching needles
    my $needles = [];
    my @tags;
    if (ref($mustmatch) eq "ARRAY") {
        my @a = @$mustmatch;
        while (my $n = shift @a) {
            if (ref($n) eq '') {
                push @tags, split(/ /, $n);
                $n = needle::tags($n);
                push @a, @$n if $n;
                next;
            }
            unless (ref($n) eq 'needle' && $n->{name}) {
                warn "invalid needle passed <" . ref($n) . "> " . bmwqemu::pp($n);
                next;
            }
            push @$needles, $n;
        }
    }
    elsif ($mustmatch) {
        $needles = needle::tags($mustmatch) || [];
        @tags = ($mustmatch);
    }

    {    # remove duplicates
        my %h = map { $_ => 1 } @tags;
        @tags = sort keys %h;
    }
    $mustmatch = join('_', @tags);

    if (!@$needles) {
        bmwqemu::diag("NO matching needles for $mustmatch");
    }

    $self->assert_screen_deadline(time + $timeout);
    $self->assert_screen_fails([]);
    $self->assert_screen_needles($needles);
    $self->assert_screen_last_check(undef);
    $self->stall_detected(0);
    $self->reload_needles($reloadneedles);
    # store them for needle reload event
    $self->assert_screen_tags(\@tags);
    return {tags => \@tags};
}

sub _time_to_assert_screen_deadline {
    my ($self) = @_;

    return $self->assert_screen_deadline - time;
}

sub reduce_deadline {
    my ($self) = @_;

    $self->assert_screen_deadline(time);
    return;
}

sub _failed_screens_to_json {
    my ($self) = @_;

    my $failed_screens = $self->assert_screen_fails;
    my $final_mismatch = $failed_screens->[-1];
    if ($final_mismatch) {
        _reduce_to_biggest_changes($failed_screens, 20);
        # only append the last mismatch if it's different to the last one in the reduced list
        my $new_final = $failed_screens->[-1];
        if ($new_final != $final_mismatch) {
            my $sim = $new_final->[0]->similarity($final_mismatch->[0]);
            push(@$failed_screens, $final_mismatch) if ($sim < 50);
        }
    }

    my @json_fails;
    for my $l (@$failed_screens) {
        my ($img, $failed_candidates, $testtime, $similarity, $filename) = @$l;
        my $h = {
            candidates => $failed_candidates,
            filename   => $self->write_img($img, $filename)};
        push(@json_fails, $h);
    }

    # free memory
    $self->assert_screen_fails([]);
    return {timeout => 1, failed_screens => \@json_fails};
}

sub check_asserted_screen {
    my ($self, $args) = @_;

    my $img = $self->last_image;
    if (!$img) {    # no screenshot yet to search on
        return;
    }

    my $img_filename = $self->_last_screenshot_name;

    my $n = $self->_time_to_assert_screen_deadline;

    my $search_ratio = 0.02;
    $search_ratio = 1 if ($n % 5 == 0);

    my ($oldimg, $old_search_ratio) = @{$self->assert_screen_last_check || ['', 0]};

    if ($n < 0) {
        # one last big search
        $search_ratio = 1;
    }
    else {
        if ($img_filename eq $oldimg && $old_search_ratio >= $search_ratio) {
            bmwqemu::diag("no change $n");
            return;
        }
    }

    my $starttime = gettimeofday;

    my ($foundneedle, $failed_candidates) = $img->search($self->assert_screen_needles, 0, $search_ratio);

    if ($foundneedle) {
        $self->assert_screen_last_check(undef);
        return {filename => $self->write_img($img, $img_filename), found => $foundneedle, candidates => $failed_candidates};
    }

    my $d = gettimeofday - $starttime;
    if ($d > $self->screenshot_interval) {
        bmwqemu::diag sprintf("WARNING: check_asserted_screen took %.2f seconds - make your needles more specific", $d);
    }

    if ($n < 0) {
        # make sure we recheck later
        $self->assert_screen_last_check(undef);

        if ($self->stall_detected) {
            backend::baseclass::write_crash_file();
            bmwqemu::mydie "assert_screen fails, but we detected a timeout in the process, so we abort";
        }
        my $failed_screens = $self->assert_screen_fails;
        # store the final mismatch
        push(@$failed_screens, [$img, $failed_candidates, 0, 1000, $img_filename]);
        my $hash = $self->_failed_screens_to_json;
        $hash->{filename} = $self->write_img($img, $img_filename);
        return $hash;
    }

    if ($search_ratio == 1) {
        # save only failures where the whole screen has been searched
        # results of partial searching are rather confusing

        # as the images create memory pressure, we only save quite different images
        # the last screen is handled automatically and the first screen is only interesting
        # if there are no others
        my $sim            = 29;
        my $failed_screens = $self->assert_screen_fails;
        if ($failed_screens->[-1] && $n > 0) {
            $sim = $failed_screens->[-1]->[0]->similarity($img);
        }
        if ($sim < 30) {
            push(@$failed_screens, [$img, $failed_candidates, $n, $sim, $img_filename]);
        }
        # clean up every once in a while to avoid excessive memory consumption.
        # The value here is an arbitrary limit.
        if (@$failed_screens > 60) {
            _reduce_to_biggest_changes($failed_screens, 20);
        }
    }
    bmwqemu::diag("no match $n");
    $self->assert_screen_last_check([$img_filename, $search_ratio]);
    return;
}

sub _reduce_to_biggest_changes {
    my ($imglist, $limit) = @_;

    return if @$imglist <= $limit;

    my $first = shift @$imglist;
    @$imglist = (sort { $b->[3] <=> $a->[3] } @$imglist)[0 .. (@$imglist > $limit ? $limit - 1 : $#$imglist)];
    unshift @$imglist, $first;

    # now sort for test time
    @$imglist = sort { $b->[2] <=> $a->[2] } @$imglist;

    # recalculate similarity
    for (my $i = 1; $i < @$imglist; ++$i) {
        $imglist->[$i]->[3] = $imglist->[$i - 1]->[0]->similarity($imglist->[$i]->[0]);
    }

    return;
}

sub freeze_vm {
    my ($self) = @_;
    bmwqemu::diag "ignored freeze_vm";
    return;
}

sub cont_vm {
    my ($self) = @_;
    bmwqemu::diag "ignored cont_vm";
    return;
}

sub last_screenshot_name {
    my ($self, $args) = @_;
    return {filename => $self->write_img($self->last_image, $self->_last_screenshot_name)};
}

sub verify_image {
    my ($self, $args) = @_;
    my $imgpath   = $args->{imgpath};
    my $mustmatch = $args->{mustmatch};

    my $img = tinycv::read($imgpath);
    my $needles = needle::tags($mustmatch) || [];

    my ($foundneedle, $failed_candidates) = $img->search($needles, 0, 1);
    if ($foundneedle) {
        return {found => $foundneedle, candidates => $failed_candidates};
    }
    return {candidates => $failed_candidates};
}


sub retry_assert_screen {
    my ($self, $args) = @_;

    if ($args->{reload_needles}) {
        for my $n (needle->all()) {
            $n->unregister();
        }
        needle::init();
    }
    # reset timeout otherwise continue wait_forneedle might just fail if stopped too long than timeout
    if ($args->{timeout}) {
        $self->assert_screen_deadline(time + $args->{timeout});
    }
    $self->cont_vm;
    # do not need to retry in 5 seconds but contining SUT if continue_waitforneedle
    if ($args->{reload_needles}) {
        # short timeout, we're already there
        $self->set_tags_to_assert({mustmatch => $self->assert_screen_tags, timeout => 5, reloadneedles => 1});

    }
    return;
}

# shared between svirt and s390 backend
sub new_ssh_connection {
    my ($self, %args) = @_;

    my $ssh = Net::SSH2->new;

    # Retry 5 times, in case of the guest is not running yet
    my $counter = 5;
    while ($counter > 0) {
        if ($ssh->connect($args{hostname})) {
            $args{username} ||= 'root';

            if ($args{password}) {
                $ssh->auth(username => $args{username}, password => $args{password});
            }
            else {
                # this relies on agent to be set up correctly
                $ssh->auth_agent($args{username});
            }
            bmwqemu::diag "Connection to $args{username}\@$args{hostname} established" if $ssh->auth_ok;
            last;
        }
        else {
            bmwqemu::diag "Could not connect to $args{username}\@$args{hostname}, Retry";
            sleep(10);
            $counter--;
            next;
        }
    }
    die "Failed to login to $args{username}\@$args{hostname}" unless $ssh->auth_ok;

    return $ssh;
}

# open another ssh connection to grab the serial console
sub start_ssh_serial {
    my ($self, %args) = @_;

    $self->stop_ssh_serial;

    $self->{serial} = $self->new_ssh_connection(%args);
    my $chan = $self->{serial}->channel();
    die "No channel found" unless $chan;
    $self->{serial_chan} = $chan;
    $chan->blocking(0);
    $chan->pty(1);
    $self->{select}->add($self->{serial}->sock);
    return $chan;
}

sub check_ssh_serial {
    my ($self, $fh) = @_;

    if ($self->{serial} && $self->{serial}->sock == $fh) {
        my $chan = $self->{serial_chan};
        my $line = <$chan>;
        if ($line) {
            print $line;
            open(my $serial, '>>', $self->{serialfile});
            print $serial $line;
            close($serial);
        }
        return 1;
    }
    return;
}

sub stop_ssh_serial {
    my ($self) = @_;

    if (!$self->{serial}) {
        return;
    }
    $self->{select}->remove($self->{serial}->sock);
    $self->{serial}->disconnect;
    $self->{serial} = undef;
    return;
}

1;
# vim: set sw=4 et:
