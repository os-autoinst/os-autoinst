# Copyright 2021 Marek Marczykowski-Górecki
# Copyright 2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package consoles::video_stream;

use Mojo::Base 'consoles::video_base', -signatures;
use Mojo::UserAgent;
use Mojo::URL;

use List::Util 'max';
use Time::HiRes qw(usleep);
use Fcntl;

use Try::Tiny;
use bmwqemu;

# speed limit: 30 keys per second
use constant STREAM_TYPING_LIMIT_DEFAULT => 30;

use constant DV_TIMINGS_CHECK_INTERVAL => 3;

use constant STALL_THRESHOLD => 4;

use constant DEFAULT_MAX_RES_X => 1680;
use constant DEFAULT_MAX_RES_Y => 1050;
use constant DEFAULT_MAX_RES => DEFAULT_MAX_RES_X * DEFAULT_MAX_RES_Y;
use constant DEFAULT_BYTES_PER_PIXEL => 3;
use constant DEFAULT_PPM_HEADER_BYTES => 20;
use constant DEFAULT_VIDEO_STREAM_PIPE_BUFFER_SIZE => DEFAULT_MAX_RES * DEFAULT_BYTES_PER_PIXEL + DEFAULT_PPM_HEADER_BYTES;

sub screen ($self, @) {
    return $self;
}

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
            $self->{dv_timings} = '';
            return;
        }
        $self->{dv_timings} = _v4l2_ctl($url, '--get-dv-timings');
    }

    my $cmd = $self->_get_ffmpeg_cmd($url);
    my $ffmpeg;
    $self->{ffmpegpid} = open($ffmpeg, '-|', @$cmd)
      or die "Failed to start ffmpeg for video stream at $url";
    # make the pipe size large enough to hold full frame and a bit
    my $frame_size = $bmwqemu::vars{VIDEO_STREAM_PIPE_BUFFER_SIZE} // DEFAULT_VIDEO_STREAM_PIPE_BUFFER_SIZE;
    fcntl($ffmpeg, Fcntl::F_SETPIPE_SZ, $frame_size);
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
    my $ret = $ffmpeg->read(my $header, DEFAULT_PPM_HEADER_BYTES);
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

sub send_key_event ($self, $key, $press_release_delay) {
    return unless $self->{input_pipe};
    $self->{input_pipe}->write($key . "\n")
      or die "failed to send '$key' input event";
}

=head2 _send_keyboard_emulator_cmd

	_send_keyboard_emulator_cmd($self, %args)

Send keyboard events using RPi Pico W based keyboard emulator

Args to be used:

	type => "hallo welt\n"
	sendkey => "ctrl-alt-del"

Intended to be used together with this device:
https://github.com/os-autoinst/os-autoinst-distri-opensuse/tree/master/data/generalhw_scripts/rpi_pico_w_keyboard

=cut

sub _send_keyboard_emulator_cmd ($self, %args) {
    my $keyboard_device_url = $bmwqemu::vars{GENERAL_HW_KEYBOARD_URL};
    my $url = Mojo::URL->new($keyboard_device_url)->query(%args);
    $self->{_ua} //= Mojo::UserAgent->new;
    my $server_response = $self->{_ua}->get($url)->result->body;
    chomp($server_response);
    bmwqemu::diag("Keyboard emulator says: " . bmwqemu::pp($server_response));
    return {};
}


sub type_string ($self, $args) {
    if ($bmwqemu::vars{GENERAL_HW_KEYBOARD_URL}) {
        return $self->_send_keyboard_emulator_cmd(type => $args->{text});
    }
    return $self->SUPER::type_string($args);
}

sub send_key ($self, $args) {
    if ($bmwqemu::vars{GENERAL_HW_KEYBOARD_URL}) {
        return $self->_send_keyboard_emulator_cmd(sendkey => $args->{key});
    }
    return $self->SUPER::send_key($args);
}

sub get_last_mouse_set ($self, @) {
    return $self->{mouse};
}

sub mouse_move_to ($self, $x, $y) {
    return unless $self->{input_pipe};
    $self->{input_pipe}->write("mouse_move $x $y\n");
    $self->{input_pipe}->flush;
    # let the event be processed before further commands
    $self->backend->run_capture_loop(.1);
}

sub mouse_button ($self, $args) {
    return unless $self->{input_pipe};
    my $button = $args->{button};
    my $bstate = $args->{bstate};
    # careful: the bits order is different than in VNC
    my $mask = {left => $bstate, right => $bstate << 1, middle => $bstate << 2}->{$button} // 0;
    bmwqemu::diag "pointer_event $mask $self->{mouse}->{x}, $self->{mouse}->{y}";
    $self->{input_pipe}->write("mouse_button $mask\n");
    $self->{input_pipe}->flush;
    return {};
}

1;
