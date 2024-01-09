# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# this is an abstract class
package backend::baseclass;

use Mojo::Base -base, -signatures;
use feature 'say';
use autodie ':all';

use Carp qw(carp confess);
use Mojo::JSON;    # booleans
use Cpanel::JSON::XS ();
use File::Copy 'cp';
use File::Basename;
use Time::HiRes qw(gettimeofday time tv_interval);
use Try::Tiny;
use POSIX qw(_exit waitpid WNOHANG);
use IO::Select;
require IPC::System::Simple;
use myjsonrpc;
use needle;
use Net::SSH2 'LIBSSH2_ERROR_EAGAIN';
use OpenQA::Benchmark::Stopwatch;
use MIME::Base64 'encode_base64';
use List::Util 'min';
use List::MoreUtils 'uniq';
use Scalar::Util 'looks_like_number';
use Mojo::File 'path';
use OpenQA::Exceptions;
use Time::Seconds;
use English -no_match_vars;
use OpenQA::NamedIOSelect;

use constant FULL_SCREEN_SEARCH_FREQUENCY => $ENV{OS_AUTOINST_FULL_SCREEN_SEARCH_FREQUENCY} // 5;
use constant FULL_UPDATE_REQUEST_FREQUENCY => $ENV{OS_AUTOINST_FULL_UPDATE_REQUEST_FREQUENCY} // 5;
use constant DEFAULT_FFMPEG_CMD => 'ffmpeg -y -hide_banner -nostats -r 24 -f image2pipe -vcodec ppm -i - -pix_fmt yuv420p';

# should be a singleton - and only useful in backend process
our $backend;

has [qw(
      update_request_interval last_update_request screenshot_interval
      last_screenshot last_image assert_screen_check
      reference_screenshot assert_screen_tags assert_screen_needles
      assert_screen_deadline assert_screen_fails assert_screen_last_check
      stall_detected
)];

sub new ($class) {
    my $self = bless({class => $class}, $class);
    $self->{started} = 0;
    $self->{serialfile} = "serial0";
    $self->{serial_offset} = 0;
    $self->{video_frame_data} = [];
    $self->{video_frame_number} = 0;
    $self->{video_encoders} = {};
    $self->{external_video_encoder_image_data} = [];
    $self->{min_image_similarity} = 10_000;
    $self->{min_video_similarity} = 10_000;
    $self->{children} = [];
    $self->{ssh_connections} = {};
    $self->{xres} = $bmwqemu::vars{XRES} // 1024;
    $self->{yres} = $bmwqemu::vars{YRES} // 768;

    return $self;
}

sub truncate_serial_file ($self) {
    open(my $sf, '>', $self->{serialfile});
    close($sf);
}

# runs in the backend process to deserialize VNC commands
sub handle_command ($self, $cmd) {
    my $func = $cmd->{cmd};
    die "not supported command: $func" unless $self->can($func);
    return $self->$func($cmd->{arguments});
}

sub die_handler ($msg) {
    chomp($msg);
    bmwqemu::fctinfo "Backend process died, backend errors are reported below in the following lines:\n$msg";
    bmwqemu::serialize_state(component => 'backend', msg => $msg);
    $backend->stop_vm();
    $backend->close_pipes();
}

sub backend_signalhandler ($sig) {
    bmwqemu::diag("backend got $sig");
    $backend->stop_vm;
}

sub run ($self, $cmdpipe, $rsppipe) {
    die "there can be only one!" if $backend;
    $backend = $self;

    $SIG{__DIE__} = \&die_handler;
    $SIG{TERM} = \&backend_signalhandler;

    my $io = IO::Handle->new();
    $io->fdopen($cmdpipe, "r") || die "r fdopen $!";
    $self->{cmdpipe} = $io;

    $io = IO::Handle->new();
    $io->fdopen($rsppipe, "w") || die "w fdopen $!";
    $rsppipe = $io;
    $io->autoflush(1);
    $self->{rsppipe} = $io;

    bmwqemu::diag "$$: cmdpipe " . fileno($self->{cmdpipe}) . ', rsppipe ' . fileno($self->{rsppipe});

    bmwqemu::diag "started mgmt loop with pid $$";

    my $select_read = $self->{select_read} = OpenQA::NamedIOSelect->new;
    my $select_write = $self->{select_write} = OpenQA::NamedIOSelect->new;
    $select_read->add($self->{cmdpipe}, "baseclass::cmdpipe");
    $select_write->add($self->{cmdpipe}, "baseclass::cmdpipe");

    $self->last_update_request("-Inf" + 0);
    $self->last_screenshot(undef);
    $self->screenshot_interval($bmwqemu::vars{SCREENSHOTINTERVAL} || .5);
    # query the VNC backend more often than we write out screenshots, so the chances
    # are high we're not writing out outdated screens
    $self->update_request_interval($self->screenshot_interval / 2);

    for my $console (values %{$testapi::distri->{consoles}}) {
        # tell the consoles who they need to talk to (in this thread)
        $console->backend($self);
    }

    $self->run_capture_loop;

    bmwqemu::diag("management process exit at " . POSIX::strftime("%F %T", gmtime));    # uncoverable statement
}

sub _write_buffered_data_to_file_handle ($self, $program_name, $array_of_buffers, $fh) {
    # write as much data as possible (this is called when $fh is ready to write)
    my $data = shift @$array_of_buffers;
    my $data_written = $fh->syswrite($data);
    die "$program_name not accepting data: $!" unless defined $data_written;

    # put remaining data it back into the queue
    unshift @$array_of_buffers, substr($data, $data_written) unless $data_written == length($data);

    # remove file handle from selects if there's no more data to write
    if (!@$array_of_buffers) {
        $self->{select_read}->remove($fh);
        $self->{select_write}->remove($fh);
    }
}

sub _check_for_screen_change ($self, $now) {
    return undef unless my $wait_screen_change = $self->{_wait_screen_change};
    my $similiarity_to_reference = $self->similiarity_to_reference(undef);
    my $elapsed = $similiarity_to_reference->{elapsed} = $now - $wait_screen_change->{starttime};
    my $screen_changed = $similiarity_to_reference->{sim} < $wait_screen_change->{similarity_level};
    my $timed_out = $similiarity_to_reference->{timed_out} = $elapsed > $wait_screen_change->{timeout};
    return undef unless $screen_changed || $timed_out;
    $self->{_wait_screen_change} = undef;    # no longer waiting for screen change
    return undef unless $self->{rsppipe};
    my %reply = (rsp => $similiarity_to_reference, json_cmd_token => $self->{_postponed_cmd_token});
    myjsonrpc::send_json($self->{rsppipe}, \%reply);
    return 1;
}

sub _check_for_still_screen ($self, $now) {
    return undef unless my $wait_still_screen = $self->{_wait_still_screen};
    my $similiarity_to_reference = $self->similiarity_to_reference(undef);
    my $elapsed = $similiarity_to_reference->{elapsed} = $now - $wait_still_screen->{starttime};
    my $screen_changed = $similiarity_to_reference->{sim} < $wait_still_screen->{similarity_level};
    my $timed_out = $elapsed > $wait_still_screen->{timeout};
    my $lastchangetime = \$wait_still_screen->{lastchangetime};
    if ($screen_changed) {
        $$lastchangetime = $now;
        $self->set_reference_screenshot({});
    }
    my $is_still = $now - $$lastchangetime >= $wait_still_screen->{stilltime};
    return undef unless $is_still || $timed_out;
    $similiarity_to_reference->{timed_out} = $is_still ? 0 : $timed_out;
    $self->{_wait_still_screen} = undef;    # no longer waiting for still screen
    my %reply = (rsp => $similiarity_to_reference, json_cmd_token => $self->{_postponed_cmd_token});
    myjsonrpc::send_json($self->{rsppipe}, \%reply);
    return 1;
}

sub do_capture ($self, $timeout = undef, $starttime = undef) {
    # Time slot buckets
    my $buckets = {};
    my $wait_time_limit = $bmwqemu::vars{_CHKSEL_RATE_WAIT_TIME} // 30;
    my $hits_limit = $bmwqemu::vars{_CHKSEL_RATE_HITS} // 30_000;

    while (1) {
        last unless $self->{cmdpipe};
        my $now = gettimeofday;
        my $time_to_timeout = "Inf" + 0;
        if (defined $timeout && defined $starttime) {
            $time_to_timeout = $timeout - ($now - $starttime);
            last if $time_to_timeout <= 0;
        }

        # lower the intervals when there is a pending wait command with `no_wait` option
        # note: Still keeping the interval at 0.1 s to avoid wasting too much CPU (corresponding to what check_screen/assert_screen
        #       also does).
        my $pending_wait_command = $self->{_wait_screen_change} || $self->{_wait_still_screen};
        my @additional_intervals = $pending_wait_command && $pending_wait_command->{no_wait} ? (0.1) : ();

        my $time_to_update_request = min($self->update_request_interval, @additional_intervals) - ($now - $self->last_update_request);
        if ($time_to_update_request <= 0) {
            $self->request_screen_update();
            $self->last_update_request($now);
            # no need to interrupt loop if VNC does not talk to us first
            $time_to_update_request = $time_to_timeout;
        }

        # if we got stalled for a long time, we assume bad hardware and report it
        if ($self->assert_screen_last_check && $now - $self->last_screenshot > $self->screenshot_interval * 20) {
            $self->stall_detected(1);
            my $diff = $now - $self->last_screenshot;
            bmwqemu::fctwarn "There is some problem with your environment, we detected a stall for $diff seconds";
        }

        # capture the screen if screenshot interval exceeded
        my $screenshot_interval = min($self->screenshot_interval, @additional_intervals);
        my $time_to_screenshot = $screenshot_interval - ($now - $self->last_screenshot);
        if ($time_to_screenshot <= 0) {
            $self->capture_screenshot();
            $self->last_screenshot($now);
            $time_to_screenshot = $screenshot_interval;
        }

        # check whether the screen has changed if waiting for a screen change and send back the result
        $self->_check_for_screen_change($now) or $self->_check_for_still_screen($now);

        my $time_to_next = min($time_to_screenshot, $time_to_update_request, $time_to_timeout);
        my ($read_set, $write_set) = IO::Select->select($self->{select_read}->select(), $self->{select_write}->select(), undef, $time_to_next);

        # We need to check the video encoder and the serial socket
        my ($video_encoder, $external_video_encoder, $other) = (0, 0, 0);
        for my $fh (@$write_set) {
            if ($fh == $self->{encoder_pipe}) {
                $self->_write_buffered_data_to_file_handle('Encoder', $self->{video_frame_data}, $fh);
                $video_encoder = 1;
            }
            elsif ($fh == $self->{external_video_encoder_cmd_pipe}) {
                $self->_write_buffered_data_to_file_handle('External encoder', $self->{external_video_encoder_image_data}, $fh);
                $external_video_encoder = 1;
            }
            else {
                next if $other;
                $other = 1;
                die "error checking socket for write: $fh\n" unless $self->check_socket($fh, 1) || $other;
            }
            last if $video_encoder == 1 && $external_video_encoder == 1 && $other;
        }

        for my $fh (@$read_set) {
            # This tries to solve the problem of half-open sockets (when reading, as writing will throw an exception)
            # There are three ways to solve this problem:
            # + Send a message either to the application protocol (null message) or to the application protocol framing (an empty message)
            #   Disadvantages: Requires changes on both ends of the communication. (for example: on SSH connection i realized that after a
            #   while I start getting "bad packet length" errors)
            # + Polling the connections (Note: This is how HTTP servers work when dealing with persistent connections)
            #    Disadvantages: False positives
            # + Change the keepalive packet settings
            #   Disadvantages: TCP/IP stacks are not required to support keepalives.
            if (fileno $fh && fileno $fh != -1) {
                # Very high limits! On a working socket, the maximum hits per 10 seconds will be around 60.
                # The maximum hits per 10 seconds saw on a half open socket was >100k
                if (check_select_rate($buckets, $wait_time_limit, $hits_limit, fileno $fh, time())) {
                    my $console = $self->{current_console}->{testapi_console};
                    my $fd_nr = fileno $fh;
                    my $cnt = $buckets->{BUCKET}{$fd_nr};
                    my $name = $self->{select_read}->get_name($fh);
                    my $msg = "The file descriptor $fd_nr ($name) hit the read attempts threshold of $hits_limit/${wait_time_limit}s by $cnt. ";
                    $msg .= "Active console '$console' is not responding, it could be a half-open socket or you need to increase _CHKSEL_RATE_HITS value. ";
                    $msg .= "Make sure the console is reachable or disable stall detection on expected disconnects with '\$console->disable_vnc_stalls', for example in case of intended machine shutdown.";
                    OpenQA::Exception::ConsoleReadError->throw(error => $msg);
                }
            }


            die "error checking socket for read: $fh\n" unless $self->check_socket($fh, 0);
            # don't check for further sockets after this one as
            # check_socket can have side effects on the sockets
            # (e.g. console resets), so better take the next socket
            # next time
            last;
        }
    }
}

=head2 run_capture_loop($timeout)

=out

=item timeout

run the loop this long in seconds, indefinitely if undef, or until the
$self->{cmdpipe} is closed, whichever occurs first.

=back

=cut

sub run_capture_loop ($self, $timeout = undef) {
    my $starttime = gettimeofday;
    $self->last_screenshot($starttime) unless $self->last_screenshot;

    eval { $self->do_capture($timeout, $starttime) };
    return unless $@;
    bmwqemu::fctwarn "capture loop failed $@";
    $self->close_pipes();
}

# wait_time_limit = seconds
# This is not sliding buckets. All the IDs inside the bucket must be over the limit!
sub check_select_rate ($buckets, $wait_time_limit, $hits_limit, $id, $time) {
    my $lower_limit = $buckets->{TIME} //= $time;
    my $upper_limit = $lower_limit + $wait_time_limit;
    if ($time > $upper_limit) {
        $buckets->{TIME} = $time;

        # This is to give the opportunity to recover, if the reboot/restart is slow
        for (keys %{$buckets->{BUCKET}}) {
            if ($buckets->{BUCKET}{$_} < $hits_limit) {
                $buckets->{BUCKET} = {$id => 1};
                return 0;
            }
        }

        return 1;
    }
    $buckets->{BUCKET}{$id}++;
    return 0;
}

sub _invoke_video_encoder ($self, $pipe_name, $display_name, @cmd) {
    my $pid = open($self->{$pipe_name}, '|-', @cmd);
    my $pipe = $self->{$pipe_name};
    $self->{video_encoders}->{$pid} = {name => $display_name, pipe => $pipe, cmd => join ' ', @cmd};
    $pipe->blocking(!!$bmwqemu::vars{VIDEO_ENCODER_BLOCKING_PIPE});
}

sub _ffmpeg_banner () { qx{ffmpeg 2>&1} // '' }

sub _auto_detect_external_video_encoder ($self) {
    my $ffmpeg_banner = _ffmpeg_banner;
    return DEFAULT_FFMPEG_CMD . ' -c:v libsvtav1 -crf 50 -preset 7' if $ffmpeg_banner =~ qr/--enable-libsvtav1(\s|$)/;
    return DEFAULT_FFMPEG_CMD . ' -c:v libvpx-vp9 -crf 35 -b:v 1500k -cpu-used 1' if $ffmpeg_banner =~ qr/--enable-libvpx(\s|$)/;
}

sub _start_external_video_encoder_if_configured ($self) {
    return 0 if $bmwqemu::vars{NOVIDEO};

    my $cmd = $bmwqemu::vars{EXTERNAL_VIDEO_ENCODER_CMD} // $self->_auto_detect_external_video_encoder or return 0;
    my $output_file_name = $bmwqemu::vars{EXTERNAL_VIDEO_ENCODER_OUTPUT_FILE_EXTENSION} // 'webm';
    my $output_file_path = "video.$output_file_name";
    $cmd .= " '$output_file_path'" unless $cmd =~ s/%OUTPUT_FILE_NAME%/$output_file_path/;

    bmwqemu::diag "Launching external video encoder: $cmd";
    $self->_invoke_video_encoder(external_video_encoder_cmd_pipe => 'external video encoder', $cmd);
    return 1;
}

sub start_encoder ($self) {
    # start external video encoder if configured
    my $has_external_video_encoder_configured = $self->_start_external_video_encoder_if_configured;

    # start internal video encoder; only start it to generate PNGs if an external video encoder is used or NOVIDEO set
    my $cwd = Cwd::getcwd;
    my @cmd = (qw(nice -n 19), "$bmwqemu::scriptdir/videoencoder", "$cwd/video.ogv");
    push(@cmd, '-n') if $bmwqemu::vars{NOVIDEO} || ($has_external_video_encoder_configured && !$bmwqemu::vars{EXTERNAL_VIDEO_ENCODER_ADDITIONALLY});
    push @cmd, '-x', $self->{xres}, '-y', $self->{yres};
    $self->_invoke_video_encoder(encoder_pipe => 'built-in video encoder', @cmd);

    # open file for recording real time clock timestamps as subtitle
    open($self->{vtt_caption_file}, '>', "$cwd/video_time.vtt");
    $self->{vtt_caption_file}->print("WEBVTT\n");

    return;
}

sub _stop_video_encoder ($self) {
    my $video_encoders = delete $self->{video_encoders};
    return undef unless defined $video_encoders && keys %$video_encoders;

    # pass remaining video frames to the video encoder
    bmwqemu::diag 'Passing remaining frames to the video encoder';
    my $timeout = 30;
    my $video_data_for_internal_encoder = $self->{video_frame_data};
    my $video_data_for_external_encoder = $self->{external_video_encoder_image_data};
    my $select = IO::Select->new;
    $select->add(my $internal_pipe = $self->{encoder_pipe}) if @$video_data_for_internal_encoder;
    $select->add(my $external_pipe = $self->{external_video_encoder_cmd_pipe}) if @$video_data_for_external_encoder;
    try {
        while ($select->count) {
            $! = 0;
            die($! ? "$!\n" : 'timeout exceeded') unless my @ready = $select->can_write($timeout);
            for my $fh (@ready) {
                if (defined $internal_pipe && $fh == $internal_pipe) {
                    $self->_write_buffered_data_to_file_handle('Encoder', $video_data_for_internal_encoder, $fh);
                    $select->remove($fh) unless @$video_data_for_internal_encoder;
                }
                elsif (defined $external_pipe && $fh == $external_pipe) {
                    $self->_write_buffered_data_to_file_handle('External encoder', $video_data_for_external_encoder, $fh);
                    $select->remove($fh) unless @$video_data_for_external_encoder;
                }
            }
        }
    }
    catch {
        bmwqemu::diag "Unable to pass remaining frames to video encoder: $_";
    };

    # give the video encoder processes time to finalize the video
    # note: Closing the pipe should cause the video encoder to terminate. Not sending SIGTERM/SIGINT because the signal might be
    #       already sent by the worker or shell and ffmpeg will not continue finalizing the video after receiving a 2nd exit signal.
    no autodie qw(close waitpid);
    close $video_encoders->{$_}->{pipe} for keys %$video_encoders;
    bmwqemu::diag 'Waiting for video encoder to finalize the video';
    for (my $interval = 0.25; $timeout > 0; sleep($interval), $timeout -= $interval) {
        for my $pid (keys %$video_encoders) {
            my $ret = waitpid($pid, WNOHANG);
            if ($ret == $pid || $ret == -1) {
                bmwqemu::diag "The $video_encoders->{$pid}->{name} (pid $pid) terminated";
                delete $video_encoders->{$pid};
            }
        }
        last unless keys %$video_encoders;
    }
    return undef unless keys %$video_encoders;
    bmwqemu::diag "Unable to terminate $video_encoders->{$_}->{name}, sending SIGKILL" for keys %$video_encoders;
    kill KILL => (keys %$video_encoders);
}

# new api

sub start_vm ($self, @) {
    $self->{started} = 1;
    $self->start_encoder();
    return $self->do_start_vm();
}

sub stop_vm ($self, @) {
    if ($self->{started}) {
        # backend.run might have disappeared already in case of failed builds
        no autodie 'unlink';
        unlink('backend.run');
        $self->do_stop_vm();
        $self->{started} = 0;
    }
    $self->_stop_video_encoder();
    $self->close_ssh_connections();
    $self->close_pipes();    # does not return
    return;
}

# new api end

# virtual methods
sub notimplemented ($self) {
    my $method = (caller(1))[3];
    $method =~ s/^backend::baseclass:://;
    confess sprintf "backend method '%s' not implemented for class '%s'",
      $method, ref $self;
}

# parameters: acpi, reset, (on), off
sub power ($self, $args) { $self->notimplemented }
sub insert_cd ($self) { $self->notimplemented }
sub eject_cd ($self, $args = {}) { $self->notimplemented }
sub do_start_vm ($self, @) { $self->notimplemented }
sub do_stop_vm ($self, @) { $self->notimplemented }
sub stop ($self) { $self->notimplemented }
sub cont ($self) { $self->notimplemented }

sub can_handle ($self, @) {
    return;    # sorry, no
}

sub do_extract_assets ($self, $args) { $self->notimplemented }

sub is_shutdown ($self, @) { -1 }

sub switch_network ($self, $args) { $self->notimplemented }

sub save_memory_dump ($self, $args) { $self->notimplemented }

sub save_storage ($self, $args) { $self->notimplemented }

## MAY be overwritten:

# vm's would return
# (userstat, systemstat)
sub cpu_stat ($self) { [] }

sub format_vtt_timestamp ($self, $walltime) {
    my $frametime_ms = 1000 * $self->{video_frame_number} / 24;
    my $caption = "\n$self->{video_frame_number}\n";
    # presentation time span (one frame)
    $caption .= sprintf(POSIX::strftime("%T.%%03d", gmtime($frametime_ms / 1000)), $frametime_ms % 1000);
    $frametime_ms += 1000 / 24;
    $caption .= " --> ";
    $caption .= sprintf(POSIX::strftime("%T.%%03d\n", gmtime($frametime_ms / 1000)), $frametime_ms % 1000);
    # clock value as caption text
    $caption .= sprintf(POSIX::strftime("[%FT%T.%%03d]\n", localtime($walltime)), 1000 * ($walltime - int($walltime)));

    return $caption;
}

sub enqueue_screenshot ($self, $image) {
    my $watch = OpenQA::Benchmark::Stopwatch->new();
    $watch->start();

    $image = $image->scale($self->{xres}, $self->{yres});
    $watch->lap("scaling");

    my $lastscreenshot = $self->last_image;

    # link identical files to save space
    my $sim = 0;
    $sim = $lastscreenshot->similarity($image) if $lastscreenshot;
    $watch->lap("similarity");

    $self->{min_image_similarity} -= 1;
    $self->{min_image_similarity} = $sim if $sim < $self->{min_image_similarity};
    $self->{min_video_similarity} -= 1;
    $self->{min_video_similarity} = $sim if $sim < $self->{min_video_similarity};

    # ensure gettimeofday returns float number, not a list of two entries
    # where we would discard the second element
    $self->{vtt_caption_file}->print($self->format_vtt_timestamp('' . gettimeofday));

    # we have two different similarity levels - one (slightly higher value, based
    # t/data/user-settings-*) to determine if it's worth it to recheck needles
    # and one (slightly lower as less significant) determining if we write the frame
    # into the video
    if ($self->{min_image_similarity} <= 54) {
        $self->last_image($image);
        $self->{min_image_similarity} = 10_000;
    }

    my $external_video_encoder_cmd_pipe = $self->{external_video_encoder_cmd_pipe};
    if ($self->{min_video_similarity} > 50) {    # we ignore smaller differences
        push(@{$self->{video_frame_data}}, "R\n");
        push(@{$self->{external_video_encoder_image_data}}, $self->{last_image_data})
          if defined $external_video_encoder_cmd_pipe && defined $self->{last_image_data};
    }
    else {
        my $imgdata = $self->{last_image_data} = $image->ppm_data;
        $watch->lap("convert ppm data");
        push(@{$self->{video_frame_data}}, 'E ' . length($imgdata) . "\n");
        push(@{$self->{video_frame_data}}, $imgdata);
        $self->{min_video_similarity} = 10_000;
        push(@{$self->{external_video_encoder_image_data}}, $imgdata)
          if defined $external_video_encoder_cmd_pipe;
    }
    my $encoder_pipe = $self->{encoder_pipe};
    $self->{select_read}->add($encoder_pipe, 'baseclass::encoder_pipe');
    $self->{select_write}->add($encoder_pipe, 'baseclass::encoder_pipe');
    if (defined $external_video_encoder_cmd_pipe) {
        $self->{select_read}->add($external_video_encoder_cmd_pipe, 'baseclass::external_video_encoder_cmd_pipe');
        $self->{select_write}->add($external_video_encoder_cmd_pipe, 'baseclass::external_video_encoder_cmd_pipe');
    }
    $self->{video_frame_number} += 1;

    $watch->stop();
    if ($watch->as_data()->{total_time} > $self->screenshot_interval && !$bmwqemu::vars{NO_DEBUG_IO}) {
        bmwqemu::fctwarn sprintf("enqueue_screenshot took %.2f seconds", $watch->as_data()->{total_time});
        bmwqemu::diag "DEBUG_IO: \n" . $watch->summary();
    }

    return;
}

sub wait_screen_change ($self, $args) {
    $args->{starttime} = gettimeofday;
    $self->{_wait_screen_change} = $args;
    return {postponed => 1};
}

sub wait_still_screen ($self, $args) {
    $args->{starttime} = $args->{lastchangetime} = gettimeofday;
    $self->set_reference_screenshot({});
    $self->{_wait_still_screen} = $args;
    return {postponed => 1};
}

sub close_pipes ($self) {
    if ($self->{cmdpipe}) {
        close($self->{cmdpipe}) || die "close $!\n";
        $self->{cmdpipe} = undef;
    }

    return unless $self->{rsppipe};

    # disarm SIGTERM handler to avoid re-entrant stop_vm call, stopping anyway
    $SIG{TERM} = 'IGNORE';

    bmwqemu::diag "sending magic and exit";
    myjsonrpc::send_json($self->{rsppipe}, {QUIT => 1});
    close($self->{rsppipe}) || die "close $!\n";
    Devel::Cover::report() if Devel::Cover->can('report');
    _exit(0);    # uncoverable statement
}

# this is called for all sockets ready to read from
sub check_socket ($self, $fh, $write = undef) {
    if ($self->{cmdpipe} && $fh == $self->{cmdpipe}) {
        return 1 if $write;
        my $cmd = myjsonrpc::read_json($self->{cmdpipe});

        if ($cmd->{cmd}) {
            my $rsp = ($self->handle_command($cmd) // 0);
            my $response = {rsp => $rsp};
            if (ref $rsp eq 'HASH' && $rsp->{postponed}) {
                $self->{_postponed_cmd_token} = $cmd->{json_cmd_token};
            } elsif ($self->{rsppipe}) {    # the command might have closed it
                $response->{json_cmd_token} = $cmd->{json_cmd_token};
                myjsonrpc::send_json($self->{rsppipe}, $response);
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
# For now, we just raise the terminal window to the front on the local-Xvnc
# DISPLAY.
#
# should we hide the other windows, somehow?
#if exists $self->{current_console} ...
# my $current_window_id = $self->{current_console}->{window_id};
# if (defined $current_window_id) {
#     system("DISPLAY=$display xdotool windowminimize --sync $current_window_id");
# }
#-> select

sub select_console ($self, $args) {
    my $testapi_console = $args->{testapi_console};

    my $selected_console = $self->console($testapi_console);
    my $activated = try {
        local $SIG{__DIE__} = 'DEFAULT';
        $selected_console->select;
    }
    catch {
        {error => $_};
    };

    return $activated if ref($activated);
    $self->{current_console} = $selected_console;
    $self->{current_screen} = $selected_console->screen;
    $self->capture_screenshot();
    return {activated => $activated};
}

sub reset_consoles ($self, $args) {
    # we iterate through all consoles
    for my $console (keys %{$testapi::distri->{consoles}}) {
        next if $self->console($console)->{args}->{persistent};
        $self->reset_console({testapi_console => $console});
    }
    return;
}

sub reset_console ($self, $args) {
    $self->console($args->{testapi_console})->reset;
    return;
}

sub deactivate_console ($self, $args) {
    my $testapi_console = $args->{testapi_console};
    my $console_info = $self->console($testapi_console);
    $self->{current_console} = undef if defined $self->{current_console} && $self->{current_console} == $console_info;
    $console_info->disable();
    return;
}

sub disable_consoles ($self) {
    for my $console (keys %{$testapi::distri->{consoles}}) {
        my $console_info = $self->console($console);
        $console_info->disable() if $console_info->can('disable');
    }
}

sub reenable_consoles ($self) {
    for my $console (keys %{$testapi::distri->{consoles}}) {
        my $console_info = $self->console($console);
        $console_info->activate() if $console_info->{activated} && $console_info->can('disable');
    }
}

=head3 save_console_snapshots

Should be called when a snapshot of the SUT is taken to save the current state
of any consoles which have state. For example: text consoles may have
unprocessed output from the SUT in their buffers which is needed by test
module after the snapshot.

=cut
sub save_console_snapshots ($self, $name) {
    for my $console (keys %{$testapi::distri->{consoles}}) {
        my $console_info = $self->console($console);
        $console_info->save_snapshot($name) if $console_info->can('save_snapshot');
    }
}

=head3 load_console_snapshots

Should be called when a snapshot of the SUT is loaded to ensure consoles are
in the same state as when the snapshot was taken.

=cut
sub load_console_snapshots ($self, $name) {
    for my $console (keys %{$testapi::distri->{consoles}}) {
        my $console_info = $self->console($console);
        $console_info->load_snapshot($name) if $console_info->can('load_snapshot');
    }
}

sub request_screen_update ($self, $args = undef) {
    return $self->bouncer('request_screen_update', $args);
}

sub console ($self, $testapi_console) {
    my $ret = $testapi::distri->{consoles}->{$testapi_console};
    carp "console $testapi_console does not exist" unless $ret;
    return $ret;
}

sub bouncer ($self, $call, $args) {
    # forward to the current VNC console
    return unless $self->{current_screen};
    return $self->{current_screen}->$call($args);
}

sub send_key ($self, $args) {
    return $self->bouncer('send_key', $args);
}

sub hold_key ($self, $args) {
    return $self->bouncer('hold_key', $args);
}

sub release_key ($self, $args) {
    return $self->bouncer('release_key', $args);
}

sub type_string ($self, $args) {
    return $self->bouncer('type_string', $args);
}

sub mouse_set ($self, $args) {
    return $self->bouncer('mouse_set', $args);
}

sub mouse_hide ($self, $args) {
    return $self->bouncer('mouse_hide', $args);
}

sub mouse_button ($self, $args) {
    return $self->bouncer('mouse_button', $args);
}

sub get_last_mouse_set ($self, $args) {
    return $self->bouncer('get_last_mouse_set', $args);
}

sub is_serial_terminal ($self, $args) {
    return {yesorno => $self->{current_console}->is_serial_terminal};
}

sub get_wait_still_screen_on_here_doc_input ($self, $args) { 0 }

sub capture_screenshot ($self) {
    return unless $self->{current_screen};

    my $screen = $self->{current_screen}->current_screen();
    $self->enqueue_screenshot($screen) if $screen;
    return;
}

sub reload_needles (@) {
    # called from testapi::set_var, so read the vars
    bmwqemu::load_vars();

    $_->unregister() for needle::all();
    needle::init();
}

###################################################################
# this is used by backend::console_proxy
sub proxy_console_call ($self, $wrapped_call) {
    my ($console, $function, $args) = @$wrapped_call{qw(console function args)};
    $console = $self->console($console);

    my $wrapped_result = {};

    eval {
        # Do not die in here.
        # Move the decision to actually die to the server side instead.
        # For this ignore backend::baseclass::die_handler.
        local $SIG{__DIE__} = 'DEFAULT';
        $wrapped_result->{result} = $wrapped_call->{wantarray} ? [$console->$function(@$args)] : $console->$function(@$args);
    };
    $wrapped_result->{exception} = join("\n", bmwqemu::pp($wrapped_call), $@) if $@;
    return $wrapped_result;
}

=head2 clear_serial_buffer

Determines the starting offset within the serial file - so that we do not check the
previous test's serial output. Call this before you start doing something new

=cut

sub clear_serial_buffer ($self, @) {
    $self->{serial_offset} = -s $self->{serialfile};
    return $self->{serial_offset};
}


=head2 serial_text

Returns the output on the serial device since the last call to clear_serial_buffer

=cut

sub serial_text ($self) {
    return ($self->read_serial($self->{serial_offset}))[0];
}

=head2 read_serial

Returns the output and the offset after reading on the serial device from position

=cut

sub read_serial ($self, $position, $whence = 0) {
    open(my $SERIAL, "<", $self->{serialfile});
    seek($SERIAL, $position, $whence);
    local $/;
    my $data = <$SERIAL>;
    my $offset = tell $SERIAL;
    close($SERIAL);

    return ($data, $offset);
}

sub wait_serial ($self, $args) {
    my $regexp = $args->{regexp};
    my $timeout = $args->{timeout};
    my $matched = 0;
    my $str;

    if ($self->{current_console} && $self->{current_console}->is_serial_terminal) {
        return $self->{current_screen}->read_until($regexp, $timeout, %$args);
    }

    $regexp = [$regexp] if ref $regexp ne 'ARRAY';
    my $initial_time = time;
    my $current_offset = $self->{serial_offset};
    while (time < $initial_time + $timeout) {
        $str = $self->serial_text();
        for my $r (@$regexp) {
            if (!$args->{no_regex} && $str =~ m/$r/) {
                $current_offset += $LAST_MATCH_END[0];
                $str = substr($str, 0, $LAST_MATCH_END[0]);
                $matched = 1;
                last;
            } elsif ($args->{no_regex} && (my $i = index($str, $r)) >= 0) {
                $current_offset += length($r) + $i;
                $str = substr($str, 0, $i + length($r));
                $matched = 1;
                last;
            }
        }
        last if ($matched);
        $self->run_capture_loop(1);
    }
    $self->{serial_offset} = $current_offset;
    return {matched => $matched, string => $str};
}

# set_reference_screenshot and similiarity_to_reference are necessary to
# implement wait_still and wait_changed functions in the tests without having
# to transfer the screenshot into the test process
sub set_reference_screenshot ($self, $args) {
    $self->reference_screenshot($self->last_image);
    return;
}

sub similiarity_to_reference ($self, $args) {
    return {sim => 10_000} if (!$self->reference_screenshot || !$self->last_image);
    return {sim => $self->reference_screenshot->similarity($self->last_image)};
}

sub set_tags_to_assert ($self, $args) {
    my $mustmatch = $args->{mustmatch};
    my $timeout = $args->{timeout} // $bmwqemu::default_timeout;

    # keep only the most recently used images (https://progress.opensuse.org/issues/15438)
    needle::clean_image_cache();

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
        $needles = [uniq @$needles];
    }
    elsif ($mustmatch) {
        $needles = needle::tags($mustmatch) || [];
        @tags = ($mustmatch);
    }

    {    # remove duplicates
        my %h = map { $_ => 1 } @tags;
        @tags = sort keys %h;
    }
    $mustmatch = join(',', @tags);
    bmwqemu::fctinfo "NO matching needles for $mustmatch" unless @$needles;

    $self->set_assert_screen_timeout($timeout);
    $self->assert_screen_fails([]);
    $self->assert_screen_needles($needles);
    $self->assert_screen_last_check(undef);
    $self->stall_detected(0);
    # store them for needle reload event
    $self->assert_screen_tags(\@tags);
    $self->assert_screen_check($args->{check});
    return {tags => \@tags};
}

sub set_assert_screen_timeout ($self, $timeout) {
    return bmwqemu::fctwarn('set_assert_screen_timeout called with non-numeric timeout') unless looks_like_number($timeout);
    $self->assert_screen_deadline(time + $timeout);
    return $self->assert_screen_deadline;
}

sub _time_to_assert_screen_deadline ($self) {
    return $self->assert_screen_deadline - time;
}

sub _failed_screens_to_json ($self) {
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
        my ($img, $failed_candidates, $testtime, $similarity, $frame) = @$l;
        my $h = {
            candidates => $failed_candidates,
            image => encode_base64($img->ppm_data),
            frame => $frame,
        };
        push(@json_fails, $h);
    }

    # free memory
    $self->assert_screen_fails([]);
    return {timeout => 1, failed_screens => \@json_fails};
}

sub time_remaining_str ($time) {
    # compensate rounding to be consistent with truncation in $search_ratio calculation
    return sprintf("%.1fs", $time - 0.05);
}

sub _reset_asserted_screen_check_variables ($self) {
    $self->{_final_full_update_requested} = 0;
    $self->assert_screen_last_check(undef);
}

sub check_asserted_screen ($self, $args) {
    return unless my $img = $self->last_image;    # no screenshot yet to search on
    my $watch = OpenQA::Benchmark::Stopwatch->new();
    my $timestamp = $self->last_screenshot;
    my $n = $self->_time_to_assert_screen_deadline;
    my $frame = $self->{video_frame_number};

    # do a full-screen search every FULL_SCREEN_SEARCH_FREQUENCY'th time and at the end
    my $search_ratio = $n < 0 || $n % FULL_SCREEN_SEARCH_FREQUENCY == 0 ? 1 : 0.02;
    my ($oldimg, $old_search_ratio) = @{$self->assert_screen_last_check || [undef, 0]};

    bmwqemu::diag('no change: ' . time_remaining_str($n)) and return if $n >= 0 && $oldimg && $oldimg eq $img && $old_search_ratio >= $search_ratio;

    $watch->start();
    $watch->{debug} = 0;

    my @registered_needles = grep { !$_->{unregistered} } @{$self->assert_screen_needles};
    my ($foundneedle, $failed_candidates) = $img->search(\@registered_needles, 0, $search_ratio, ($watch->{debug} ? $watch : undef));
    $watch->lap("Needle search") unless $watch->{debug};
    if ($foundneedle) {
        $self->_reset_asserted_screen_check_variables;
        return {
            image => encode_base64($img->ppm_data),
            found => $foundneedle,
            candidates => $failed_candidates,
            frame => $frame,
        };
    }

    $watch->stop();
    if ($watch->as_data()->{total_time} > $self->screenshot_interval) {
        bmwqemu::fctwarn sprintf(
            "check_asserted_screen took %.2f seconds for %d candidate needles - make your needles more specific",
            $watch->as_data()->{total_time},
            scalar(@registered_needles));
        bmwqemu::diag "DEBUG_IO: \n" . $watch->summary() if (!$bmwqemu::vars{NO_DEBUG_IO} && $watch->{debug});
    }

    my $no_match_diag = 'no match: ' . time_remaining_str($n);
    if (my $best_candidate = $failed_candidates->[0]) {
        $no_match_diag .= sprintf(
            ", best candidate: %s (%.2f)",
            $best_candidate->{needle}->{name},
            1 - sqrt($best_candidate->{error})
        );
    }
    bmwqemu::diag($no_match_diag);

    if ($n < 0) {
        $self->_reset_asserted_screen_check_variables;

        if (!$self->assert_screen_check) {
            my @unregistered_needles = grep { $_->{unregistered} } @{$self->assert_screen_needles};
            my ($foundneedle, $candidates) = $img->search(\@unregistered_needles, 0, 1, undef);
            # the best here is still a failure, as unregistered
            push(@$failed_candidates, $foundneedle) if $foundneedle;
            push(@$failed_candidates, @$candidates);
        }
        my $failed_screens = $self->assert_screen_fails;
        # store the final mismatch
        push(@$failed_screens, [$img, $failed_candidates, 0, 1000, $frame]);
        my $hash = $self->_failed_screens_to_json;
        $hash->{image} = encode_base64($img->ppm_data);
        # store stall status
        $hash->{stall} = $self->stall_detected;

        return $hash;
    }
    elsif ($n <= $self->screenshot_interval * 2 && !$self->{_final_full_update_requested}) {
        # try to request a full screen update to workaround possibly destorted VNC screen
        # as we're nearing the deadline
        $self->request_screen_update({incremental => 0});
        $self->{_final_full_update_requested} = 1;
    }
    elsif ($n % FULL_UPDATE_REQUEST_FREQUENCY == 0) {
        $self->request_screen_update({incremental => 0});
    }

    if ($search_ratio == 1) {
        # save only failures where the whole screen has been searched
        # results of partial searching are rather confusing

        # as the images create memory pressure, we only save quite different images
        # the last screen is handled automatically and the first screen is only interesting
        # if there are no others
        my $sim = 29;
        my $failed_screens = $self->assert_screen_fails;
        if ($failed_screens->[-1] && $n > 0) {
            $sim = $failed_screens->[-1]->[0]->similarity($img);
        }
        if ($sim < 30) {
            push(@$failed_screens, [$img, $failed_candidates, $n, $sim, $frame]);
        }
        # clean up every once in a while to avoid excessive memory consumption.
        # The value here is an arbitrary limit.
        if (@$failed_screens > 60) {
            _reduce_to_biggest_changes($failed_screens, 20);
        }
    }
    $self->assert_screen_last_check([$img, $search_ratio]);
    return;
}

sub _reduce_to_biggest_changes ($imglist, $limit) {
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

sub freeze_vm ($self, @) {
    bmwqemu::diag "ignored freeze_vm";
    return;
}

sub cont_vm ($self, @) {
    bmwqemu::diag "ignored cont_vm";
    return;
}

sub last_screenshot_data ($self, $args) {
    return {} unless $self->last_image;
    return {
        image => encode_base64($self->last_image->ppm_data),
        frame => $self->{video_frame_number},
    };
}

sub verify_image ($self, $args) {
    my $imgpath = $args->{imgpath};
    my $mustmatch = $args->{mustmatch};

    my $img = tinycv::read($imgpath);
    my $needles = needle::tags($mustmatch) || [];

    my ($foundneedle, $failed_candidates) = $img->search($needles, 0, 1);
    return {found => $foundneedle, candidates => $failed_candidates} if $foundneedle;
    return {candidates => $failed_candidates};
}

sub retry_assert_screen ($self, $args) {
    $self->reload_needles if $args->{reload_needles};
    # reset timeout otherwise continue wait_forneedle might just fail if stopped too long than timeout
    $self->set_assert_screen_timeout($args->{timeout}) if $args->{timeout};
    $self->cont_vm;
    # do not need to retry in 5 seconds but contining SUT if continue_waitforneedle
    if ($args->{reload_needles}) {
        # short timeout, we're already there
        $self->set_tags_to_assert({mustmatch => $self->assert_screen_tags, timeout => 5, reloadneedles => 1});
    }
    return;
}

# shared between svirt and s390 backend
sub new_ssh_connection ($self, %args) {
    bmwqemu::log_call(%{$self->hide_password(%args)});
    my %credentials = $self->get_ssh_credentials;
    $args{$_} //= $credentials{$_} foreach (keys(%credentials));
    $args{username} ||= 'root';
    $args{port} ||= 22;
    $args{keep_open} //= 0;
    my $connection_key;

    # e.g. using hyperv_intermediate host which is running Windows need to keep the connection.
    # Otherwise a mount point doesn't exists within the next command.
    if ($args{keep_open}) {
        $connection_key = join(',', map { $_ . "=" . $args{$_} } qw(hostname username port));
        my $con = $self->{ssh_connections}->{$connection_key};
        if (defined($con)) {
            # Check if we still can create channels on that connection
            if (my $tmp_chan = $con->channel()) {
                $tmp_chan->close();
                bmwqemu::diag "Using existing SSH connection (key:$connection_key)";
                return $con;
            } else {
                bmwqemu::diag "Closing broken SSH connection (key:$connection_key)";
                $con->disconnect();
                delete $self->{ssh_connections}->{$connection_key};
            }
        }
    }

    # timeout requires libssh2 >= 1.2.9 so not all versions might have it
    my $ssh = Net::SSH2->new(timeout => ($bmwqemu::vars{SSH_COMMAND_TIMEOUT_S} // 5 * ONE_MINUTE) * 1000);

    # Retry multiple times, in case of the guest is not running yet
    my $counter = $bmwqemu::vars{SSH_CONNECT_RETRY} // 5;
    my $con_pretty = "$args{username}\@$args{hostname}";
    $con_pretty .= ":$args{port}" unless $args{port} == 22;
    while ($counter > 0) {
        if ($ssh->connect($args{hostname}, $args{port})) {

            if (!$args{use_ssh_agent} && defined($args{password})) {
                $ssh->auth(username => $args{username}, password => $args{password});
            }
            else {
                # this relies on agent to be set up correctly
                $ssh->auth_agent($args{username});
            }
            bmwqemu::diag "SSH connection to $con_pretty established" if $ssh->auth_ok;
            last;
        }
        else {
            bmwqemu::diag "Could not connect to $con_pretty, Retrying after some seconds...";
            sleep($bmwqemu::vars{SSH_CONNECT_RETRY_INTERVAL} // 10);
            $counter--;
            next;
        }
    }
    OpenQA::Exception::SSHConnectionError->throw(error => "Error connecting to <$con_pretty>: $@") unless $ssh->auth_ok;

    $self->{ssh_connections}->{$connection_key} = $ssh if ($args{keep_open});
    return $ssh;
}

=head2 get_ssh_credentials
Should return a hash with the keys: C<hostname, username, password, port>
The keys port and username are optional and default to 22 and 'root', respectively.
=cut
sub get_ssh_credentials ($self) { }

# open another ssh connection to grab the serial console
sub start_ssh_serial ($self, %args) {
    bmwqemu::log_call(%{$self->hide_password(%args)});
    $self->stop_ssh_serial;

    my $ssh = $self->{serial} = $self->new_ssh_connection(%args);
    my $chan = $self->{serial_chan} = $ssh->channel();
    $ssh->die_with_error("Unable to establish SSH channel for serial console") unless $chan;
    $chan->blocking(0);
    $chan->pty(1);
    $chan->ext_data('merge');
    $self->{select_read}->add($ssh->sock);
    return ($ssh, $chan);
}

sub check_ssh_serial ($self, $fh = undef, $write = undef) {
    my $ssh = $self->{serial};
    return 0 unless $ssh;
    my $ssh_socket = $ssh->sock;
    return 0 unless $ssh_socket == $fh;

    if ($write) {
        bmwqemu::fctwarn 'SSH serial: setup error: socket has been wrongly selected for writing';
        return 1;
    }

    # read from SSH channel (receiving extended data channel as well via `$chan->ext_data('merge')`)
    my $chan = $self->{serial_chan};
    my $buffer;
    while (defined(my $bytes_read = $chan->read($buffer, 4096))) {
        return 1 unless $bytes_read > 0;
        print $buffer;
        open(my $serial, '>>', $self->{serialfile});
        print $serial $buffer;
        close($serial);
    }

    my ($error_code, $error_name, $error_string) = $ssh->error;
    return 1 if $error_code == LIBSSH2_ERROR_EAGAIN;

    bmwqemu::fctwarn "ssh serial: unable to read: $error_string (error code: $error_code) - closing connection";
    $self->stop_ssh_serial();
    return 1;
}

=head2 run_ssh_cmd

   $ret = run_ssh_cmd($cmd [, username => ?][, password => ?][,host => ?]);
   ($ret, $stdout, $stderr) = run_ssh_cmd($cmd [, username => ?][, password => ?][,host => ?], wantarray => 1);

=cut
sub run_ssh_cmd ($self, $cmd, %args) {
    my ($stdout, $stderr) = ('', '');
    $args{wantarray} //= 0;
    $args{keep_open} //= 1;

    bmwqemu::log_call(cmd => $cmd, %{$self->hide_password(%args)});
    my ($ssh, $chan) = $self->run_ssh($cmd, %args);
    $chan->send_eof;

    until ($chan->eof) {
        if (my ($o, $e) = $chan->read2) {
            $stdout .= $o;
            $stderr .= $e;
        }
    }

    bmwqemu::diag("[run_ssh_cmd($cmd)] stdout:$/$stdout") if length($stdout);
    bmwqemu::diag("[run_ssh_cmd($cmd)] stderr:$/$stderr") if length($stderr);
    my $ret = $chan->exit_status();
    bmwqemu::diag("[run_ssh_cmd($cmd)] exit-code: $ret");
    $ssh->disconnect() unless $args{keep_open};

    return $args{wantarray} ? ($ret, $stdout, $stderr) : $ret;
}

sub run_ssh ($self, $cmd, %args) {
    bmwqemu::log_call(cmd => $cmd, %{$self->hide_password(%args)});
    $args{blocking} //= 1;
    my $ssh = $self->new_ssh_connection(%args);
    my $chan = $ssh->channel() || $ssh->die_with_error("Unable to create SSH channel for executing \"$cmd\"");
    $chan->exec($cmd) || $ssh->die_with_error("Unable to execute \"$cmd\"");
    $ssh->blocking($args{blocking});
    return ($ssh, $chan);
}

sub close_ssh_connections ($self) {
    my $cons = $self->{ssh_connections} // {};
    for my $key (keys(%{$cons})) {
        bmwqemu::diag("SSH disconnect $key");
        $cons->{$key}->disconnect();
        delete($cons->{$key});
    }
}

sub stop_ssh_serial ($self) {
    my $ssh = $self->{serial};
    return undef unless $ssh;
    bmwqemu::diag('Closing SSH serial connection with ' . $ssh->hostname);
    $self->{select_read}->remove($ssh->sock);
    $ssh->disconnect;
    $self->{serial_chan} = undef;
    return $self->{serial} = undef;
}

sub hide_password ($self, %args) {
    $args{password} = 'SECRET' if $args{password};
    return \%args;
}

sub handle_deprecate_backend ($backend) {
    my $deprecation_message = <<"EOF";
DEPRECATED: 'backend::$backend' is unsupported and planned to be
removed from os-autoinst eventually. If the backend is still needed please
report an issue on https://github.com/os-autoinst/os-autoinst . This message
can be temporarily turned into a warning by setting the environment variable
'OS_AUTOINST_NO_DEPRECATE_BACKEND_$backend' or the os-autoinst variable
'NO_DEPRECATE_BACKEND_$backend'
EOF
    die $deprecation_message unless $bmwqemu::vars{"NO_DEPRECATE_BACKEND_$backend"} || $ENV{"OS_AUTOINST_NO_DEPRECATE_BACKEND_$backend"};
    log::fctwarn $deprecation_message;
}

# Send TERM signal to any child process
sub _stop_children_processes ($self) {
    my $ret;
    for my $pid (@{$self->{children}}) {
        bmwqemu::diag("terminating child $pid");
        kill('TERM', $pid);
        for my $i (1 .. 5) {
            $ret = waitpid($pid, WNOHANG);
            bmwqemu::diag "waitpid for $pid returned $ret";
            last if ($ret == $pid);
            sleep 1;    # uncoverable statement
        }
    }
}

sub _child_process ($self, $code) {
    die "Can't spawn child without code" unless ref($code) eq "CODE";

    my $pid = fork();
    die "fork failed" unless defined($pid);    # uncoverable statement

    if ($pid == 0) {
        $code->();    # uncoverable statement
    }
    else {
        push @{$self->{children}}, $pid;
        return $pid;
    }

}

1;
