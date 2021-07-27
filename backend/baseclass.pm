# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2020 SUSE LLC
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
use feature 'say';
use autodie ':all';

use Carp qw(carp confess);
use Mojo::JSON;    # booleans
use Cpanel::JSON::XS ();
use File::Copy 'cp';
use File::Basename;
use Time::HiRes qw(gettimeofday time tv_interval);
use Try::Tiny;
use POSIX qw(_exit :sys_wait_h);
use IO::Select;
require IPC::System::Simple;
use myjsonrpc;
use Net::SSH2 'LIBSSH2_ERROR_EAGAIN';
use OpenQA::Benchmark::Stopwatch;
use MIME::Base64 'encode_base64';
use List::Util 'min';
use List::MoreUtils 'uniq';
use Scalar::Util 'looks_like_number';
use Mojo::File 'path';
use OpenQA::Exceptions;

# should be a singleton - and only useful in backend process
our $backend;

use parent 'Class::Accessor::Fast';
__PACKAGE__->mk_accessors(
    qw(
      update_request_interval last_update_request screenshot_interval
      last_screenshot last_image assert_screen_check
      reference_screenshot assert_screen_tags assert_screen_needles
      assert_screen_deadline assert_screen_fails assert_screen_last_check
      stall_detected
    ));

sub new {
    my $class = shift;
    my $self  = bless({class => $class}, $class);
    $self->{started}                           = 0;
    $self->{serialfile}                        = "serial0";
    $self->{serial_offset}                     = 0;
    $self->{video_frame_data}                  = [];
    $self->{video_frame_number}                = 0;
    $self->{video_encoders}                    = {};
    $self->{external_video_encoder_image_data} = [];
    $self->{min_image_similarity}              = 10000;
    $self->{min_video_similarity}              = 10000;
    $self->{children}                          = [];
    $self->{ssh_connections}                   = {};

    return $self;
}

sub truncate_serial_file {
    my ($self) = @_;
    open(my $sf, '>', $self->{serialfile});
    close($sf);
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
    chomp($msg);
    bmwqemu::fctinfo "Backend process died, backend errors are reported below in the following lines:\n$msg";
    bmwqemu::serialize_state(component => 'backend', msg => $msg);
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

    bmwqemu::diag "$$: cmdpipe " . fileno($self->{cmdpipe}) . ', rsppipe ' . fileno($self->{rsppipe});

    bmwqemu::diag "started mgmt loop with pid $$";

    my $select_read  = $self->{select_read}  = IO::Select->new;
    my $select_write = $self->{select_write} = IO::Select->new;
    $select_read->add($self->{cmdpipe});
    $select_write->add($self->{cmdpipe});

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

    bmwqemu::diag("management process exit at " . POSIX::strftime("%F %T", gmtime));
}

sub _write_buffered_data_to_file_handle {
    my ($self, $program_name, $array_of_buffers, $fh) = @_;

    # write as much data as possible (this is called when $fh is ready to write)
    my $data         = shift @$array_of_buffers;
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

=head2 run_capture_loop($timeout)

=out

=item timeout

run the loop this long in seconds, indefinitely if undef, or until the
$self->{cmdpipe} is closed, whichever occurs first.

=back

=cut

sub run_capture_loop {
    my ($self, $timeout) = @_;
    my $starttime = gettimeofday;
    if (!$self->last_screenshot) {
        my $now = gettimeofday;
        $self->last_screenshot($now);
    }

    eval {
        # Time slot buckets
        my $buckets         = {};
        my $wait_time_limit = $bmwqemu::vars{_CHKSEL_RATE_WAIT_TIME} // 30;
        my $hits_limit      = $bmwqemu::vars{_CHKSEL_RATE_HITS}      // 15_000;

        while (1) {
            last if (!$self->{cmdpipe});

            my $now             = gettimeofday;
            my $time_to_timeout = "Inf" + 0;
            if (defined $timeout) {
                $time_to_timeout = $timeout - ($now - $starttime);

                last if $time_to_timeout <= 0;
            }

            my $time_to_update_request = $self->update_request_interval - ($now - $self->last_update_request);
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

            my $time_to_screenshot = $self->screenshot_interval - ($now - $self->last_screenshot);
            if ($time_to_screenshot <= 0) {
                $self->capture_screenshot();
                $self->last_screenshot($now);
                $time_to_screenshot = $self->screenshot_interval;
            }

            my $time_to_next = min($time_to_screenshot, $time_to_update_request, $time_to_timeout);
            my ($read_set, $write_set) = IO::Select->select($self->{select_read}, $self->{select_write}, undef, $time_to_next);

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
                    if (!$self->check_socket($fh, 1) && !$other) {
                        die "huh! $fh\n";
                    }
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
                    if (check_select_rate($buckets, $wait_time_limit, $hits_limit, fileno $fh)) {
                        my $console = $self->{current_console}->{testapi_console};
                        OpenQA::Exception::ConsoleReadError->throw(error => "The console '$console' is not responding (half-open socket?). Make sure the console is reachable or disable stall detection on expected disconnects with '\$console->disable_vnc_stalls', for example in case of intended machine shutdown");
                    }
                }


                unless ($self->check_socket($fh, 0)) {
                    die "huh! $fh\n";
                }
                # don't check for further sockets after this one as
                # check_socket can have side effects on the sockets
                # (e.g. console resets), so better take the next socket
                # next time
                last;
            }
        }
    };

    if ($@) {
        bmwqemu::fctwarn "capture loop failed $@";
        $self->close_pipes();
    }
    return;
}

# wait_time_limit = seconds
# This is not sliding buckets. All the IDs inside the bucket must be over the limit!
sub check_select_rate {
    my ($buckets, $wait_time_limit, $hits_limit, $id) = @_;

    my $time        = gettimeofday;
    my $lower_limit = $time;

    if ($buckets->{TIME}) {
        $lower_limit = $buckets->{TIME};
    }
    else {
        # Bucket initialization;
        $buckets->{TIME} = $time;
    }

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

sub _invoke_video_encoder {
    my ($self, $pipe_name, $display_name, @cmd) = @_;

    my $pid  = open($self->{$pipe_name}, '|-', @cmd);
    my $pipe = $self->{$pipe_name};
    $self->{video_encoders}->{$pid} = {name => $display_name, pipe => $pipe};
    $pipe->blocking(0);
}

sub _start_external_video_encoder_if_configured {
    my ($self) = @_;

    return 0 if $bmwqemu::vars{NOVIDEO};

    my $cmd              = $bmwqemu::vars{EXTERNAL_VIDEO_ENCODER_CMD} or return 0;
    my $output_file_name = $bmwqemu::vars{EXTERNAL_VIDEO_ENCODER_OUTPUT_FILE_EXTENSION} // 'webm';
    my $output_file_path = Cwd::getcwd . "/video.$output_file_name";
    $cmd .= " '$output_file_path'" unless $cmd =~ s/%OUTPUT_FILE_NAME%/$output_file_path/;

    bmwqemu::diag "Launching external video encoder: $cmd";
    $self->_invoke_video_encoder(external_video_encoder_cmd_pipe => 'external video encoder', $cmd);
    return 1;
}

sub start_encoder {
    my ($self) = @_;

    # start external video encoder if configured
    my $has_external_video_encoder_configured = $self->_start_external_video_encoder_if_configured;

    # start internal video encoder; only start it to generate PNGs if an external video encoder is used or NOVIDEO set
    my $cwd = Cwd::getcwd;
    my @cmd = (qw(nice -n 19), "$bmwqemu::scriptdir/videoencoder", "$cwd/video.ogv");
    push(@cmd, '-n') if $bmwqemu::vars{NOVIDEO} || ($has_external_video_encoder_configured && !$bmwqemu::vars{EXTERNAL_VIDEO_ENCODER_ADDITIONALLY});
    $self->_invoke_video_encoder(encoder_pipe => 'built-in video encoder', @cmd);

    # open file for recording real time clock timestamps as subtitle
    open($self->{vtt_caption_file}, '>', "$cwd/video_time.vtt");
    $self->{vtt_caption_file}->print("WEBVTT\n");

    return;
}

sub _stop_video_encoder {
    my ($self) = @_;

    my $video_encoders = delete $self->{video_encoders};
    return undef unless defined $video_encoders && keys %$video_encoders;

    # pass remaining video frames to the video encoder
    bmwqemu::diag 'Passing remaining frames to the video encoder';
    my $timeout                         = 30;
    my $video_data_for_internal_encoder = $self->{video_frame_data};
    my $video_data_for_external_encoder = $self->{external_video_encoder_image_data};
    my $select                          = IO::Select->new;
    $select->add(my $internal_pipe = $self->{encoder_pipe})                    if @$video_data_for_internal_encoder;
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

sub start_vm {
    my ($self) = @_;
    $self->{started} = 1;
    $self->start_encoder();
    return $self->do_start_vm();
}

sub stop_vm {
    my ($self) = @_;
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

sub alive {
    my ($self) = @_;
    if ($self->{started}) {
        if ($self->file_alive() and $self->raw_alive()) {
            return 1;
        }
        else {
            bmwqemu::fctwarn 'backend.run got deleted! - exiting...';
            _exit(1);
        }
    }
    return 0;
}

# new api end

# virtual methods
sub notimplemented { confess "backend method not implemented" }

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

sub is_shutdown { -1 }

sub save_memory_dump { notimplemented }

sub save_storage_drives { notimplemented }

## MAY be overwritten:

sub cpu_stat {
    # vm's would return
    # (userstat, systemstat)
    return [];
}

sub format_vtt_timestamp {
    my ($self, $walltime) = @_;

    my $frametime_ms = 1000 * $self->{video_frame_number} / 24;
    my $caption      = "\n$self->{video_frame_number}\n";
    # presentation time span (one frame)
    $caption .= sprintf(POSIX::strftime("%T.%%03d", gmtime($frametime_ms / 1000)), $frametime_ms % 1000);
    $frametime_ms += 1000 / 24;
    $caption .= " --> ";
    $caption .= sprintf(POSIX::strftime("%T.%%03d\n", gmtime($frametime_ms / 1000)), $frametime_ms % 1000);
    # clock value as caption text
    $caption .= sprintf(POSIX::strftime("[%FT%T.%%03d]\n", localtime($walltime)), 1000 * ($walltime - int($walltime)));

    return $caption;
}

sub enqueue_screenshot {
    my ($self, $image) = @_;

    return unless $image;

    my $watch = OpenQA::Benchmark::Stopwatch->new();
    $watch->start();

    $image = $image->scale(1024, 768);
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

    $self->{vtt_caption_file}->print($self->format_vtt_timestamp(gettimeofday));

    # we have two different similarity levels - one (slightly higher value, based
    # t/data/user-settings-*) to determine if it's worth it to recheck needles
    # and one (slightly lower as less significant) determining if we write the frame
    # into the video
    if ($self->{min_image_similarity} <= 54) {
        $self->last_image($image);
        $self->{min_image_similarity} = 10000;
    }

    my $external_video_encoder_cmd_pipe = $self->{external_video_encoder_cmd_pipe};
    if ($self->{min_video_similarity} > 50) {    # we ignore smaller differences
        push(@{$self->{video_frame_data}},                  "R\n");
        push(@{$self->{external_video_encoder_image_data}}, $self->{last_image_data})
          if defined $external_video_encoder_cmd_pipe && defined $self->{last_image_data};
    }
    else {
        my $imgdata = $self->{last_image_data} = $image->ppm_data;
        $watch->lap("convert ppm data");
        push(@{$self->{video_frame_data}}, 'E ' . length($imgdata) . "\n");
        push(@{$self->{video_frame_data}}, $imgdata);
        $self->{min_video_similarity} = 10000;
        push(@{$self->{external_video_encoder_image_data}}, $imgdata)
          if defined $external_video_encoder_cmd_pipe;
    }
    my $encoder_pipe = $self->{encoder_pipe};
    $self->{select_read}->add($encoder_pipe);
    $self->{select_write}->add($encoder_pipe);
    if (defined $external_video_encoder_cmd_pipe) {
        $self->{select_read}->add($external_video_encoder_cmd_pipe);
        $self->{select_write}->add($external_video_encoder_cmd_pipe);
    }
    $self->{video_frame_number} += 1;

    $watch->stop();
    if ($watch->as_data()->{total_time} > $self->screenshot_interval && !$bmwqemu::vars{NO_DEBUG_IO}) {
        bmwqemu::diag sprintf("WARNING: enqueue_screenshot took %.2f seconds", $watch->as_data()->{total_time});
        bmwqemu::diag "DEBUG_IO: \n" . $watch->summary();
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
    myjsonrpc::send_json($self->{rsppipe}, {QUIT => 1});
    close($self->{rsppipe}) || die "close $!\n";
    Devel::Cover::report() if Devel::Cover->can('report');
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
                myjsonrpc::send_json($self->{rsppipe}, $rsp);
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

sub select_console {
    my ($self, $args) = @_;
    my $testapi_console = $args->{testapi_console};

    my $selected_console = $self->console($testapi_console);
    my $activated        = try {
        local $SIG{__DIE__} = 'DEFAULT';
        $selected_console->select;
    }
    catch {
        {error => $_};
    };

    return $activated if ref($activated);
    $self->{current_console} = $selected_console;
    $self->{current_screen}  = $selected_console->screen;
    $self->capture_screenshot();
    return {activated => $activated};
}

sub reset_consoles {
    my ($self, $args) = @_;

    # we iterate through all consoles
    for my $console (keys %{$testapi::distri->{consoles}}) {
        next if $self->console($console)->{args}->{persistent};
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

sub disable_consoles {
    my ($self) = @_;

    for my $console (keys %{$testapi::distri->{consoles}}) {
        my $console_info = $self->console($console);
        if ($console_info->can('disable')) {
            $console_info->disable();
        }
    }
}

sub reenable_consoles {
    my ($self) = @_;

    for my $console (keys %{$testapi::distri->{consoles}}) {
        my $console_info = $self->console($console);
        if ($console_info->{activated} && $console_info->can('disable')) {
            $console_info->activate();
        }
    }
}

=head3 save_console_snapshots

Should be called when a snapshot of the SUT is taken to save the current state
of any consoles which have state. For example: text consoles may have
unprocessed output from the SUT in their buffers which is needed by test
module after the snapshot.

=cut
sub save_console_snapshots {
    my ($self, $name) = @_;

    for my $console (keys %{$testapi::distri->{consoles}}) {
        my $console_info = $self->console($console);
        if ($console_info->can('save_snapshot')) {
            $console_info->save_snapshot($name);
        }
    }
}

=head3 load_console_snapshots

Should be called when a snapshot of the SUT is loaded to ensure consoles are
in the same state as when the snapshot was taken.

=cut
sub load_console_snapshots {
    my ($self, $name) = @_;

    for my $console (keys %{$testapi::distri->{consoles}}) {
        my $console_info = $self->console($console);
        if ($console_info->can('load_snapshot')) {
            $console_info->load_snapshot($name);
        }
    }
}

sub request_screen_update {
    my ($self) = @_;
    return $self->bouncer('request_screen_update', undef);
}

sub console {
    my ($self, $testapi_console) = @_;

    my $ret = $testapi::distri->{consoles}->{$testapi_console};
    carp "console $testapi_console does not exist" unless $ret;
    return $ret;
}

sub bouncer {
    my ($self, $call, $args) = @_;
    # forward to the current VNC console
    return unless $self->{current_screen};
    return $self->{current_screen}->$call($args);
}

sub send_key {
    my ($self, $args) = @_;
    return $self->bouncer('send_key', $args);
}

sub hold_key {
    my ($self, $args) = @_;
    return $self->bouncer('hold_key', $args);
}

sub release_key {
    my ($self, $args) = @_;
    return $self->bouncer('release_key', $args);
}

sub type_string {
    my ($self, $args) = @_;
    return $self->bouncer('type_string', $args);
}

sub mouse_set {
    my ($self, $args) = @_;
    return $self->bouncer('mouse_set', $args);
}

sub mouse_hide {
    my ($self, $args) = @_;
    return $self->bouncer('mouse_hide', $args);
}

sub mouse_button {
    my ($self, $args) = @_;
    return $self->bouncer('mouse_button', $args);
}

sub get_last_mouse_set {
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

sub reload_needles {
    # called from testapi::set_var, so read the vars
    bmwqemu::load_vars();

    for my $n (needle->all()) {
        $n->unregister();
    }
    needle::init();
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
        $wrapped_result->{result} = $wrapped_call->{wantarray} ? [$console->$function(@$args)] : $console->$function(@$args);
    };
    $wrapped_result->{exception} = join("\n", bmwqemu::pp($wrapped_call), $@) if $@;
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
    return ($self->read_serial($self->{serial_offset}))[0];
}

=head2 read_serial

Returns the output and the offset after reading on the serial device from position

=cut

sub read_serial {
    my ($self, $position, $whence) = @_;

    open(my $SERIAL, "<", $self->{serialfile});
    seek($SERIAL, $position, $whence // 0);
    local $/;
    my $data   = <$SERIAL>;
    my $offset = tell $SERIAL;
    close($SERIAL);

    return ($data, $offset);
}

sub wait_serial {
    my ($self, $args) = @_;

    my $regexp  = $args->{regexp};
    my $timeout = $args->{timeout};
    my $matched = 0;
    my $str;

    confess '\'current_console\' is not set' unless $self->{current_console};
    if ($self->{current_console}->is_serial_terminal) {
        return $self->{current_screen}->read_until($regexp, $timeout, %$args);
    }

    $regexp = [$regexp] if ref $regexp ne 'ARRAY';
    my $initial_time = time;
    while (time < $initial_time + $timeout) {
        $str = $self->serial_text();
        for my $r (@$regexp) {
            $matched = ref $r eq 'Regexp' ? $str =~ $r : $str =~ m/$r/;
            if ($matched) {
                $regexp = "$r";
                last;
            }
        }
        last if ($matched);
        $self->run_capture_loop(1);
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
    return {sim => 10000} if (!$self->reference_screenshot || !$self->last_image);
    return {sim => $self->reference_screenshot->similarity($self->last_image)};
}

sub set_tags_to_assert {
    my ($self, $args) = @_;
    my $mustmatch = $args->{mustmatch};
    my $timeout   = $args->{timeout} // $bmwqemu::default_timeout;

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
        @tags    = ($mustmatch);
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

sub set_assert_screen_timeout {
    my ($self, $timeout) = @_;
    return bmwqemu::fctwarn('set_assert_screen_timeout called with non-numeric timeout') unless looks_like_number($timeout);
    $self->assert_screen_deadline(time + $timeout);
}

sub _time_to_assert_screen_deadline {
    my ($self) = @_;

    return $self->assert_screen_deadline - time;
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
        my ($img, $failed_candidates, $testtime, $similarity, $frame) = @$l;
        my $h = {
            candidates => $failed_candidates,
            image      => encode_base64($img->ppm_data),
            frame      => $frame,
        };
        push(@json_fails, $h);
    }

    # free memory
    $self->assert_screen_fails([]);
    return {timeout => 1, failed_screens => \@json_fails};
}

sub time_remaining_str {
    my $time = shift;
    # compensate rounding to be consistent with truncation in $search_ratio calculation
    return sprintf("%.1fs", $time - 0.05);
}

sub check_asserted_screen {
    my ($self, $args) = @_;

    my $img = $self->last_image;
    return unless $img;    # no screenshot yet to search on
    my $watch     = OpenQA::Benchmark::Stopwatch->new();
    my $timestamp = $self->last_screenshot;
    my $n         = $self->_time_to_assert_screen_deadline;
    my $frame     = $self->{video_frame_number};

    my $search_ratio = 0.02;
    $search_ratio = 1 if ($n % 5 == 0);

    my ($oldimg, $old_search_ratio) = @{$self->assert_screen_last_check || [undef, 0]};

    if ($n < 0) {
        # one last big search
        $search_ratio = 1;
    }
    else {
        if ($oldimg && $oldimg eq $img && $old_search_ratio >= $search_ratio) {
            bmwqemu::diag('no change: ' . time_remaining_str($n));
            return;
        }
    }

    $watch->start();
    $watch->{debug} = 0;

    my @registered_needles = grep { !$_->{unregistered} } @{$self->assert_screen_needles};
    my ($foundneedle, $failed_candidates) = $img->search(\@registered_needles, 0, $search_ratio, ($watch->{debug} ? $watch : undef));
    $watch->lap("Needle search") unless $watch->{debug};
    if ($foundneedle) {
        $self->assert_screen_last_check(undef);
        return {
            image      => encode_base64($img->ppm_data),
            found      => $foundneedle,
            candidates => $failed_candidates,
            frame      => $frame,
        };
    }

    $watch->stop();
    if ($watch->as_data()->{total_time} > $self->screenshot_interval) {
        bmwqemu::diag sprintf(
            "WARNING: check_asserted_screen took %.2f seconds for %d candidate needles - make your needles more specific",
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
        # make sure we recheck later
        $self->assert_screen_last_check(undef);

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

sub last_screenshot_data {
    my ($self, $args) = @_;
    return {} unless $self->last_image;
    return {
        image => encode_base64($self->last_image->ppm_data),
        frame => $self->{video_frame_number},
    };
}

sub verify_image {
    my ($self, $args) = @_;
    my $imgpath   = $args->{imgpath};
    my $mustmatch = $args->{mustmatch};

    my $img     = tinycv::read($imgpath);
    my $needles = needle::tags($mustmatch) || [];

    my ($foundneedle, $failed_candidates) = $img->search($needles, 0, 1);
    return {found      => $foundneedle, candidates => $failed_candidates} if $foundneedle;
    return {candidates => $failed_candidates};
}

sub retry_assert_screen {
    my ($self, $args) = @_;

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
sub new_ssh_connection {
    my ($self, %args) = @_;
    bmwqemu::log_call(%{$self->hide_password(%args)});
    my %credentials = $self->get_ssh_credentials;
    $args{$_} //= $credentials{$_} foreach (keys(%credentials));
    $args{username} ||= 'root';
    $args{port}     ||= 22;
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
                bmwqemu::diag "Use existing SSH connection (key:$connection_key)";
                return $con;
            } else {
                bmwqemu::diag "Close broken SSH connection (key:$connection_key)";
                $con->disconnect();
                delete $self->{ssh_connections}->{$connection_key};
            }
        }
    }

    my $ssh = Net::SSH2->new;

    # Retry multiple times, in case of the guest is not running yet
    my $counter    = $bmwqemu::vars{SSH_CONNECT_RETRY} // 5;
    my $con_pretty = "$args{username}\@$args{hostname}";
    $con_pretty .= ":$args{port}" unless $args{port} == 22;
    while ($counter > 0) {
        if ($ssh->connect($args{hostname}, $args{port})) {

            if ($args{password}) {
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
sub get_ssh_credentials {
    return;
}

# open another ssh connection to grab the serial console
sub start_ssh_serial {
    my ($self, %args) = @_;
    bmwqemu::log_call(%{$self->hide_password(%args)});
    $self->stop_ssh_serial;

    my $ssh  = $self->{serial}      = $self->new_ssh_connection(%args);
    my $chan = $self->{serial_chan} = $ssh->channel();
    $ssh->die_with_error("Unable to establish SSH channel for serial console") unless $chan;
    $chan->blocking(0);
    $chan->pty(1);
    $chan->ext_data('merge');
    $self->{select_read}->add($ssh->sock);
    return ($ssh, $chan);
}

sub check_ssh_serial {
    my ($self, $fh, $write) = @_;

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
sub run_ssh_cmd {
    my ($self, $cmd, %args) = @_;
    my ($stdout, $stderr) = ('', '');
    $args{wantarray} //= 0;
    $args{keep_open} //= 1;

    bmwqemu::log_call(cmd => $cmd, %{$self->hide_password(%args)});
    my ($ssh, $chan) = $self->run_ssh($cmd, %args);
    $chan->send_eof;

    while (!$chan->eof) {
        if (my ($o, $e) = $chan->read2) {
            $stdout .= $o;
            $stderr .= $e;
        }
    }

    bmwqemu::diag("[run_ssh_cmd($cmd)] stdout:$/$stdout") if length($stdout);
    bmwqemu::diag("[run_ssh_cmd($cmd)] stderr:$/$stderr") if length($stderr);
    my $ret = $chan->exit_status();
    bmwqemu::diag("[run_ssh_cmd($cmd)] exit-code: $ret");
    $ssh->disconnect() unless ($args{keep_open});

    return $args{wantarray} ? ($ret, $stdout, $stderr) : $ret;
}

sub run_ssh {
    my ($self, $cmd, %args) = @_;
    bmwqemu::log_call(cmd => $cmd, %{$self->hide_password(%args)});
    $args{blocking} //= 1;
    my $ssh  = $self->new_ssh_connection(%args);
    my $chan = $ssh->channel() || $ssh->die_with_error("Unable to create SSH channel for executing \"$cmd\"");
    $chan->exec($cmd) || $ssh->die_with_error("Unable to execute \"$cmd\"");
    $ssh->blocking($args{blocking});
    return ($ssh, $chan);
}

sub close_ssh_connections {
    my $self = shift;
    my $cons = $self->{ssh_connections} // {};
    for my $key (keys(%{$cons})) {
        bmwqemu::diag("SSH disconnect $key");
        $cons->{$key}->disconnect();
        delete($cons->{$key});
    }
}

sub stop_ssh_serial {
    my ($self) = @_;

    my $ssh = $self->{serial};
    return undef unless $ssh;
    bmwqemu::diag('Closing SSH serial connection with ' . $ssh->hostname);
    $self->{select_read}->remove($ssh->sock);
    $ssh->disconnect;
    $self->{serial_chan} = undef;
    return $self->{serial} = undef;
}

sub hide_password {
    my ($self, %args) = @_;
    $args{password} = 'SECRET' if ($args{password});
    return \%args;
}

# Send TERM signal to any child process
sub _stop_children_processes {
    my ($self) = @_;
    my $ret;
    for my $pid (@{$self->{children}}) {
        bmwqemu::diag("terminating child $pid");
        kill('TERM', $pid);
        for my $i (1 .. 5) {
            $ret = waitpid($pid, WNOHANG);
            bmwqemu::diag "waitpid for $pid returned $ret";
            last if ($ret == $pid);
            sleep 1;
        }
    }
}

sub _child_process {
    my ($self, $code) = @_;

    die "Can't spawn child without code" unless ref($code) eq "CODE";

    my $pid = fork();
    die "fork failed" unless defined($pid);

    if ($pid == 0) {
        $code->();
    }
    else {
        push @{$self->{children}}, $pid;
        return $pid;
    }

}

1;
