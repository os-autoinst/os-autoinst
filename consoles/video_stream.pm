# Copyright 2021 Marek Marczykowski-Górecki
# Copyright 2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package consoles::video_stream;

use Mojo::Base 'consoles::video_stream', -signatures;

use List::Util 'max';
use Time::HiRes qw(usleep);

use Try::Tiny;
use bmwqemu ();

use constant DV_TIMINGS_CHECK_INTERVAL => 3;

use constant STALL_THRESHOLD => 4;

my $CHARMAP = {
    "\t" => 'tab',
    "\n" => 'ret',
    "\b" => 'backspace',
    "\e" => 'esc',
    " " => 'spc',
};

sub disable_video ($self) {
    my $ret = 0;
    if ($self->{ffmpeg}) {
        kill(TERM => $self->{ffmpegpid});
        close($self->{ffmpeg});
        $self->{ffmpeg} = undef;
        $ret = waitpid($self->{ffmpegpid}, 0);
        $self->{ffmpegpid} = undef;
    }
    return $ret;
}

sub disable ($self, @) {
    my $ret = $self->disable_video;
    if ($self->{input_pipe}) {
        close($self->{input_pipe});
        waitpid($self->{inputpid}, 0);
    }
    return $ret;
}

sub _v4l2_ctl ($device, $cmd) {
    my @cmd = ("v4l2-ctl", "--device", $device, "--concise");
    push(@cmd, split(/ /, $cmd));
    my $pipe;
    my $pid = open($pipe, '-|', @cmd) or return undef;
    $pipe->read(my $str, 50);
    my $ret = waitpid($pid, 0);
    if ($ret > 0 && $? == 0) {
        # remove header and whitespaces
        $str =~ s/DV timings://;
        $str =~ s/^\s+|\s+$//g;
        return $str;
    }
    return undef;
}

sub connect_remote ($self, $args) {
    $self->{_last_update_received} = 0;

    if ($args->{url} =~ m/^\/dev\/video/) {
        if ($args->{edid}) {
            my $ret = _v4l2_ctl($args->{url}, "--set-edid $args->{edid}");
            die "Failed to set EDID" unless defined $ret;
        }

        my $timings = _v4l2_ctl($args->{url}, '--get-dv-timings');
        if ($timings) {
            if ($timings ne "0x0pnan") {
                $self->{dv_timings} = $timings;
            } else {
                $self->{dv_timings} = '';
            }
            $self->{dv_timings_supported} = 1;
            $self->{dv_timings_last_check} = time;
            bmwqemu::diag "Current DV timings: $timings";
        } else {
            $self->{dv_timings_supported} = 0;
            bmwqemu::diag "DV timings not supported";
        }
    } else {
        # applies to v4l only
        $self->{dv_timings_supported} = 0;
    }

    bmwqemu::diag "Starting to receive video stream at $args->{url}";
    $self->connect_remote_video($args->{url});

    $self->connect_remote_input($args->{input_cmd}) if $args->{input_cmd};
}

sub _get_ffmpeg_cmd ($self, $url) {
    my @cmd = ('ffmpeg', '-loglevel', 'fatal', '-i', $url);
    push(@cmd, ('-vcodec', 'ppm', '-f', 'rawvideo', '-r', '2', '-'));
    return \@cmd;
}

sub connect_remote_video ($self, $url) {
    if ($self->{dv_timings_supported}) {
        if (!_v4l2_ctl($url, '--set-dv-bt-timings query')) {
            bmwqemu::diag("No video signal");
            return;
        }
        $self->{dv_timings} = _v4l2_ctl($url, '--get-dv-timings');
    }

    my $cmd = $self->_get_ffmpeg_cmd($url);
    my $ffmpeg;
    $self->{ffmpegpid} = open($ffmpeg, '-|', @$cmd)
      or die "Failed to start ffmpeg for video stream at $url";
    $self->{ffmpeg} = $ffmpeg;
    $ffmpeg->blocking(0);

    $self->{_last_update_received} = time;

    return 1;
}

sub connect_remote_input ($self, $cmd) {
    $self->{mouse} = {x => -1, y => -1};

    bmwqemu::diag "Connecting input device";

    my $input_pipe;
    $self->{inputpid} = open($input_pipe, '|' . $cmd)
      or die "Failed to start input_cmd($cmd)";
    $self->{input_pipe} = $input_pipe;
    $self->{input_pipe}->autoflush(1);

    return $input_pipe;
}


sub _receive_frame ($self) {
    my $ffmpeg = $self->{ffmpeg};
    $ffmpeg or die 'ffmpeg is not running. Probably your backend instance could not start or died.';
    $ffmpeg->blocking(0);
    my $ret = $ffmpeg->read(my $header, 20);
    $ffmpeg->blocking(1);

    return undef unless $ret;

    die "ffmpeg closed: $ret\n${\Dumper $self}" unless $ret > 0;

    # support P6 only
    if (!($header =~ m/^(P6\n(\d+) (\d+)\n(\d+)\n)/)) {
        die "Invalid PPM header: $header";
    }
    my $header_len = length($1);
    my $width = $2;
    my $height = $3;
    my $bytes_per_pixel = ($4 < 256) ? 1 : 2;
    my $frame_len = $width * $height * 3 * $bytes_per_pixel;
    my $remaining_len = $header_len + $frame_len - $ret;
    $ret = $ffmpeg->read(my $frame_data, $remaining_len);
    die "Incomplete frame (got $ret instead of $remaining_len)" if $ret != $remaining_len;
    my $img = tinycv::from_ppm($header . $frame_data);
    $self->{_framebuffer} = $img;
    $self->{width} = $width;
    $self->{height} = $height;
    $self->{_last_update_received} = time;
    return $img;
}

sub update_framebuffer ($self) {
    if ($self->{dv_timings_supported}) {
        # periodically check if DV timings needs update due to resolution change
        if (time - $self->{dv_timings_last_check} >= DV_TIMINGS_CHECK_INTERVAL) {
            my $current_timings = _v4l2_ctl($self->{args}->{url}, '--query-dv-timings');
            if ($current_timings && $current_timings ne $self->{dv_timings}) {
                bmwqemu::diag "Updating DV timings, new: $current_timings";
                # yes, there is need to update DV timings, restart ffmpeg,
                # connect_remote_video will update the timings
                $self->disable_video;
                $self->connect_remote_video($self->{args}->{url});
            } elsif ($self->{dv_timings} && !$current_timings) {
                bmwqemu::diag "video disconnected";
                $self->disable_video;
                $self->{dv_timings} = '';
            }
            $self->{dv_timings_last_check} = time;
        }
    }

    # no video connected, don't read anything
    return 0 unless $self->{ffmpeg};

    my $have_recieved_update = 0;
    while ($self->_receive_frame()) {
        $have_recieved_update = 1;
    }
    return $have_recieved_update;
}

sub current_screen ($self) {
    $self->update_framebuffer();
    return unless $self->{_framebuffer};
    return $self->{_framebuffer};
}

sub request_screen_update ($self, @) {
    if (!$self->update_framebuffer()) {
        # check if it isn't stalled, perhaps we missed resolution change?
        my $time_since_last_update = time - $self->{_last_update_received};
        if ($self->{ffmpeg} && $time_since_last_update > STALL_THRESHOLD) {
            # reconnect, it will refresh the device settings too
            $self->disable_video;
            $self->connect_remote_video($self->{args}->{url});
        }
    }
}

sub send_key ($self, $args) {
    $self->_send_key_event($args->{key});
    $self->backend->run_capture_loop(.2);
    return {};
}

sub _send_key_event ($self, $key) {
    return unless $self->{input_pipe};
    $self->{input_pipe}->write($key . "\n")
      or die "failed to send '$key' input event";
}

sub _mouse_move ($self, $x, $y) {
    die "need parameter \$x and \$y" unless (defined $x and defined $y);
    return unless $self->{input_pipe};

    if ($self->{mouse}->{x} == $x && $self->{mouse}->{y} == $y) {
        # in case the mouse is moved twice to the same position
        # (e.g. in case of duplicated mouse_hide), we need to wiggle the
        # mouse a bit to avoid qemu ignoring the repositioning
        # because the SUT might have moved the mouse itself and we
        # need to make sure the mouse is really where expected
        my $delta = 5;
        # move it to the left in case the mouse is right
        #$delta = -5 if $x > $self->{width} / 2;
        $delta = -5 if $x > 1024 / 2;
        $self->_mouse_move($x + $delta, $y);
    }

    bmwqemu::diag "mouse_move to $x, $y";
    $self->{input_pipe}->write("mouse_move $x $y\n");
    $self->{input_pipe}->flush;

    $self->{mouse}->{x} = $x;
    $self->{mouse}->{y} = $y;
    # let the event be processed before further commands
    $self->backend->run_capture_loop(.1);

    return;
}

sub mouse_hide ($self, $args) {
    $args->{border_offset} //= 0;

    #my $x = $self->{width} - 1;
    #my $y = $self->{height} - 1;
    my $x = 1024 - 1;
    my $y = 768 - 1;

    if (defined $args->{border_offset}) {
        my $border_offset = int($args->{border_offset});
        $x -= $border_offset;
        $y -= $border_offset;
    }

    $self->_mouse_move($x, $y);
    return {absolute => $self->{mouse}};
}

sub mouse_set ($self, $args) {
    die "Need x/y arguments" unless (defined $args->{x} && defined $args->{y});

    $self->_mouse_move(int($args->{x}), int($args->{y}));
    return {};
}

sub send_pointer_event ($self, $mask) {
    $self->{input_pipe}->write("mouse_button $mask\n");
    $self->{input_pipe}->flush;
}

1;
