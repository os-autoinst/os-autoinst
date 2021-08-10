# Copyright 2021 Marek Marczykowski-Górecki
# Copyright 2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package consoles::video_stream;

use Mojo::Base 'consoles::video_base', -signatures;

use List::Util 'max';
use Time::HiRes qw(usleep);

use Try::Tiny;
use testapi 'get_var';
use bmwqemu;

# speed limit: 30 keys per second
use constant STREAM_TYPING_LIMIT_DEFAULT => 30;

sub screen ($self, @) {
    return $self;
}

sub disable ($self, @) {
    return unless $self->{ffmpeg};
    kill(TERM => $self->{ffmpegpid});
    close($self->{ffmpeg});
    $self->{ffmpeg} = undef;
    my $ret = waitpid($self->{ffmpegpid}, 0);
    $self->{ffmpegpid} = undef;
    if ($self->{input_pipe}) {
        close($self->{input_pipe});
        waitpid($self->{inputpid}, 0);
    }
    return $ret;
}

sub _get_ffmpeg_cmd ($self, $url) {
    my @cmd = ('ffmpeg', '-loglevel', 'fatal', '-i', $url);
    push(@cmd, ('-vcodec', 'ppm', '-f', 'rawvideo', '-r', '2', '-'));
    return \@cmd;
}

sub connect_remote ($self, $args) {
    bmwqemu::diag "Starting receiving HDbitT stream at TODO";
    my $cmd = $self->_get_ffmpeg_cmd($args->{url});
    my $ffmpeg;
    $self->{ffmpegpid} = open($ffmpeg, '-|', @$cmd)
      or die "Failed to start ffmpeg for video stream at $url";
    $self->{ffmpeg} = $ffmpeg;
    $ffmpeg->blocking(0);

    $self->connect_remote_input($args->{input_cmd}) if $args->{input_cmd};

    return $ffmpeg;
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
    return $img;
}

sub update_framebuffer ($self) {
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
    $self->update_framebuffer();
# TODO? just wait
}

sub send_key_event ($self, $key, $press_release_delay) {
    return unless $self->{input_pipe};
    $self->{input_pipe}->write($key . "\n")
      or die "failed to send '$key' input event";
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
