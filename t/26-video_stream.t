#!/usr/bin/perl
# Copyright 2021 Marek Marczykowski-Górecki
# Copyright 2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Config;
use Test::Most;
use Mojo::Base -strict, -signatures;
use Mojo::UserAgent;
use Mojo::Transaction::HTTP;
use Test::Warnings qw(:all :report_warnings);
use File::Basename;
use File::Copy;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::MockModule;
use Test::MockObject;
use Test::Fatal;

use consoles::video_stream;
use tinycv;

my $data_dir = dirname(__FILE__) . '/data/';

my $mock_console = Test::MockModule->new('consoles::video_stream');
my %v4l2_ctl_results = ();
my @v4l2_ctl_calls;
$mock_console->redefine(_v4l2_ctl => sub {
        push @v4l2_ctl_calls, [@_];
        return $v4l2_ctl_results{$_[2]} || $v4l2_ctl_results{''};
});
my $mock_video_source = '/dev/null';
$mock_console->redefine(_get_ffmpeg_cmd => sub ($self, $url) {
        my @cmd = ('cat', $mock_video_source);
        return \@cmd;
});
$mock_console->redefine(_get_ustreamer_cmd => ["true"]);

my $mock_backend = Test::MockObject->new();
$mock_backend->{xres} = 1024;
$mock_backend->{yres} = 768;
$mock_backend->mock('run_capture_loop', sub { });

my $mock_bmwqemu = Test::MockModule->new('bmwqemu');
$mock_bmwqemu->noop('diag', 'fctinfo', 'log_call');

subtest 'connect stream' => sub {
    my $console = consoles::video_stream->new(undef, {url => 'udp://@:5004'});
    $console->connect_remote({url => 'udp://@:5004'});
    is $console->{dv_timings_supported}, 0, "correctly detected non-v4l2 stream";
    is_deeply \@v4l2_ctl_calls, [], "calls to v4l2-ctl";

    @v4l2_ctl_calls = ();
    %v4l2_ctl_results = ('' => '');
    $console->connect_remote({url => '/dev/video0'});
    is $console->{dv_timings_supported}, 0, "still no need to use v4l2-ctl";
    is_deeply \@v4l2_ctl_calls, [[('/dev/video0', undef, '--get-dv-timings')]], "calls to v4l2-ctl";

    @v4l2_ctl_calls = ();
    # no input connected
    %v4l2_ctl_results = ('--get-dv-timings' => '0x0pnan');
    $console->connect_remote({url => '/dev/video0'});
    is $console->{dv_timings_supported}, 1, "use v4l2-ctl";
    is $console->{dv_timings}, '', "correct lack of resolution";
    is_deeply \@v4l2_ctl_calls, [
        [('/dev/video0', undef, '--get-dv-timings')],
        [('/dev/video0', undef, '--set-dv-bt-timings query')],
    ], "calls to v4l2-ctl";

    @v4l2_ctl_calls = ();
    %v4l2_ctl_results = (
        '--get-dv-timings' => '640x480p60',
        '--set-dv-bt-timings query' => 'BT timings set',
    );
    $console->connect_remote({url => '/dev/video0'});
    is $console->{dv_timings_supported}, 1, "use v4l2-ctl";
    is $console->{dv_timings}, '640x480p60', "correct resolution";
    is_deeply \@v4l2_ctl_calls, [
        [('/dev/video0', undef, '--get-dv-timings')],
        [('/dev/video0', undef, '--set-dv-bt-timings query')],
        [('/dev/video0', undef, '--get-dv-timings')],
    ], "calls to v4l2-ctl";

    @v4l2_ctl_calls = ();
    %v4l2_ctl_results = (
        '--set-edid type=hdmi' => "CTA-861 Header\n...\n\nHDMI Vendor-Specific Data Block\n...\n",
        '--get-dv-timings' => '640x480p60',
        '--set-dv-bt-timings query' => 'BT timings set',
    );
    $console->connect_remote({url => '/dev/video0', edid => 'type=hdmi'});
    is $console->{dv_timings_supported}, 1, "use v4l2-ctl and set edid";
    is_deeply \@v4l2_ctl_calls, [
        [('/dev/video0', undef, '--set-edid type=hdmi')],
        [('/dev/video0', undef, '--get-dv-timings')],
        [('/dev/video0', undef, '--set-dv-bt-timings query')],
        [('/dev/video0', undef, '--get-dv-timings')],
    ], "calls to v4l2-ctl";

    my $cmd = $mock_console->original('_get_ffmpeg_cmd')->($console, 'udp://@:5004');
    is_deeply $cmd, [
        'ffmpeg', '-loglevel', 'fatal', '-i', 'udp://@:5004',
        '-vcodec', 'ppm', '-f', 'rawvideo', '-r', 4, '-'], "correct cmd built for UDP source";

    $cmd = $mock_console->original('_get_ffmpeg_cmd')->($console, '/dev/video0?fps=3');
    is_deeply $cmd, [
        'ffmpeg', '-loglevel', 'fatal', '-i', '/dev/video0',
        '-vcodec', 'ppm', '-f', 'rawvideo', '-r', 3, '-'], "correct cmd built for fps=3";
};

subtest 'connect stream ustreamer' => sub {
    plan skip_all => 'unsupported arch' unless ($Config{archname} =~ /^aarch64|x86_64/);
    my $console = consoles::video_stream->new(undef, {url => 'udp://@:5004'});
    @v4l2_ctl_calls = ();
    copy($data_dir . "frame1.ppm", '/dev/shm/raw-sink-dev-video0.raw');
    $console->connect_remote({url => 'ustreamer:///dev/video0'});
    is $console->{dv_timings_supported}, 0, "correctly skipping DV timing";
    is_deeply \@v4l2_ctl_calls, [], "calls to v4l2-ctl";

    my $cmd = $mock_console->original('_get_ustreamer_cmd')->($console, '/dev/video0', 'raw-sink-dev-video0.raw');
    is_deeply $cmd, [
        'ustreamer', '--device', '/dev/video0', '-f', '5',
        '-m', 'UYVY',
        '-c', 'NOOP',
        '--raw-sink', 'raw-sink-dev-video0.raw', '--raw-sink-rm',
        '--dv-timings'], "correct cmd built for ustreamer";
    $cmd = $mock_console->original('_get_ustreamer_cmd')->($console, '/dev/video0?fps=2', 'raw-sink-dev-video0.raw');
    is_deeply $cmd, [
        'ustreamer', '--device', '/dev/video0', '-f', '2',
        '-m', 'UYVY',
        '-c', 'NOOP',
        '--raw-sink', 'raw-sink-dev-video0.raw', '--raw-sink-rm',
        '--dv-timings'], "correct cmd built for fps=2";
};

subtest 'frames parsing' => sub {
    my ($img, $received_img);
    my $console = consoles::video_stream->new(undef, {url => 'udp://@:5004'});
    $mock_video_source = $data_dir . "frame1.ppm";
    $console->activate;

    $img = tinycv::read($data_dir . "frame1.png");
    $received_img = $console->current_screen();
    ok $received_img, 'current screen available to read for single frame' or return;
    is $received_img->similarity($img), 1_000_000, "received correct frame";
    $console->disable_video;

    # now two frames
    $mock_video_source = $data_dir . "frames12.ppm";
    $console->connect_remote({url => 'udp://@:5004'});

    $img = tinycv::read($data_dir . "frame2.png");
    $received_img = $console->current_screen();
    ok $received_img, 'current screen available to read for second frame' or return;
    is $received_img->similarity($img), 1_000_000, "received correct frame";
    $console->disable_video;

    # now incomplete frame
    $mock_video_source = $data_dir . "incompleteframe.ppm";
    $console->connect_remote({url => 'udp://@:5004'});

    # make sure cat process has finished to guarantee that pipe has data on the
    # next call to update_framebuffer()
    waitpid($console->{ffmpegpid}, 0);

    my $received_update = $console->update_framebuffer();
    is $received_update, 0, "detected incomplete frame";
    $console->disable_video;
};

subtest 'frame parsing - ustreamer' => sub {
    # ustreamer requires pack("D") support, not availabe in openSUSE Leap 15.5's Perl
    eval { $_ = pack("D", 1.0); };
    plan skip_all => 'packing long double is not supported' if $@;
    # frame unpacking is only correct on little-endian 64-bit arches, in
    # practice ustreamer is only used on aarch64, restrict tests to
    # aarch64 and x86_64 (x86_64 for CI convenience)
    # see https://progress.opensuse.org/issues/161969
    plan skip_all => 'unsupported arch' unless ($Config{archname} =~ /^aarch64|x86_64/);

    my ($img, $received_img);

    # ustreamer frame, invalid magic
    copy($data_dir . "frame1.ppm", '/dev/shm/raw-sink-dev-video0.raw');
    my $console = consoles::video_stream->new(undef, {url => 'ustreamer:///dev/video0'});
    $console->connect_remote({url => 'ustreamer:///dev/video0'});

    my $received_update = $console->update_framebuffer();
    is $received_update, 0, "detected invalid data";
    $console->disable_video;

    # ustreamer frame, unsupported version
    copy($data_dir . "ustreamer6-invalid", '/dev/shm/raw-sink-dev-video0.raw');
    $console = consoles::video_stream->new(undef, {url => 'ustreamer:///dev/video0'});
    $console->connect_remote({url => 'ustreamer:///dev/video0'});
    throws_ok { $console->update_framebuffer(); }
    qr/Unsupported ustreamer version '6'/, "detected unsupported version";
    $console->disable_video;

    # ustreamer frame, "no signal" message encoded as JPEG
    copy($data_dir . "ustreamer-shared-no-signal", '/dev/shm/raw-sink-dev-video0.raw');
    $console->connect_remote({url => 'ustreamer:///dev/video0'});

    $img = tinycv::read($data_dir . "ustreamer-shared-no-signal.png");
    $received_img = $console->current_screen();
    ok $received_img, 'current screen available to read for JPEG frame' or return;
    is $received_img->similarity($img), 1_000_000, "received correct JPEG frame";
    $console->disable_video;

    # ustreamer frame, actual data, encoded as UYVY
    copy($data_dir . "ustreamer-shared-full-frame", '/dev/shm/raw-sink-dev-video0.raw');
    $console->connect_remote({url => 'ustreamer:///dev/video0'});

    $img = tinycv::read($data_dir . "ustreamer-shared-full-frame.png");
    $received_img = $console->current_screen();
    ok $received_img, 'current screen available to read for UYVY frame' or return;
    is $received_img->similarity($img), 1_000_000, "received correct UYVY frame";
    $console->disable_video;

    # ustreamer v7 frame, "no signal" message encoded as RGB3
    copy($data_dir . "ustreamer7-shared-no-signal", '/dev/shm/raw-sink-dev-video0.raw');
    $console->connect_remote({url => 'ustreamer:///dev/video0'});

    $img = tinycv::read($data_dir . "ustreamer7-shared-no-signal.png");
    $received_img = $console->current_screen();
    ok $received_img, 'current screen available to read for RGB3 v7 no-signal message' or return;
    is $received_img->similarity($img), 1_000_000, "received correct RGB3 v7 no-signal message";
    $console->disable_video;

    # ustreamer v7 frame, full frame encoded as RGB3
    copy($data_dir . "ustreamer7-shared-full-frame-rgb3", '/dev/shm/raw-sink-dev-video0.raw');
    $console->connect_remote({url => 'ustreamer:///dev/video0'});

    $img = tinycv::read($data_dir . "ustreamer7-shared-full-frame-rgb3.png");
    $received_img = $console->current_screen();
    ok $received_img, 'current screen available to read for RGB3 v7 frame' or return;
    is $received_img->similarity($img), 1_000_000, "received correct RGB3 v7 frame";
    $console->disable_video;

    # ustreamer v7 frame, actual data, encoded as UYVY
    copy($data_dir . "ustreamer7-shared-full-frame", '/dev/shm/raw-sink-dev-video0.raw');
    $console->connect_remote({url => 'ustreamer:///dev/video0'});

    $img = tinycv::read($data_dir . "ustreamer7-shared-full-frame.png");
    $received_img = $console->current_screen();
    ok $received_img, 'current screen available to read for UYVY v7 frame' or return;
    is $received_img->similarity($img), 1_000_000, "received correct UYVY v7 frame";
    $console->disable_video;
};

subtest 'v4l2 resolution' => sub {
    $mock_video_source = $data_dir . "frame1.ppm";
    my $console = consoles::video_stream->new(undef, {
            url => '/dev/video0',
            video_cmd_prefix => 'ssh host',
    });
    %v4l2_ctl_results = (
        '--get-dv-timings' => '640x480p60',
        '--set-dv-bt-timings query' => 'BT timings set',
    );
    $console->activate;
    is $console->{dv_timings}, '640x480p60', 'correct resolution detected';
    @v4l2_ctl_calls = ();

    # still the same resolution
    %v4l2_ctl_results = (
        '--query-dv-timings' => '640x480p60',
    );
    $console->{dv_timings_last_check} = time - 4;

    $console->update_framebuffer();
    is $console->{dv_timings}, '640x480p60', 'correct resolution detected';
    is_deeply \@v4l2_ctl_calls, [
        [('/dev/video0', 'ssh host', '--query-dv-timings')],
    ], "calls to v4l2-ctl";

    @v4l2_ctl_calls = ();

    # changed resolution
    %v4l2_ctl_results = (
        '--query-dv-timings' => '1024x768p60',
        '--get-dv-timings' => '1024x768p60',
        '--set-dv-bt-timings query' => 'BT timings set',
    );
    $console->{dv_timings_last_check} = time - 4;

    $console->update_framebuffer();
    is $console->{dv_timings}, '1024x768p60', 'correct resolution detected';
    is_deeply \@v4l2_ctl_calls, [
        [('/dev/video0', 'ssh host', '--query-dv-timings')],
        [('/dev/video0', 'ssh host', '--set-dv-bt-timings query')],
        [('/dev/video0', 'ssh host', '--get-dv-timings')],
    ], "calls to v4l2-ctl";
    $console->disable_video;
};

subtest 'input events' => sub {
    my ($cmds_fh, @cmds);
    my $console = consoles::video_stream->new(undef, {
            url => 'udp://@:5004',
            input_cmd => "socat -lf /dev/null STDIO 'EXEC:yes ok!!CREATE:input-commands'",
    });
    $console->backend($mock_backend);
    $console->activate;

    $console->mouse_set({x => 320, y => 420});
    $console->mouse_set({x => 320, y => 420});
    $console->mouse_button({button => 'left', bstate => 1});
    $console->mouse_button({button => 'left', bstate => 0});
    $console->mouse_button({button => 'middle', bstate => 1});
    $console->mouse_button({button => 'middle', bstate => 0});
    $console->mouse_button({button => 'right', bstate => 1});
    $console->mouse_button({button => 'right', bstate => 0});
    $console->mouse_hide({});

    $console->disable;
    ok open($cmds_fh, 'input-commands'), 'open input-commands';
    @cmds = <$cmds_fh>;
    is_deeply \@cmds, [
        "mouse_move 320 420\n",
        "mouse_move 325 420\n",
        "mouse_move 320 420\n",
        "mouse_button 1\n",
        "mouse_button 0\n",
        "mouse_button 4\n",
        "mouse_button 0\n",
        "mouse_button 2\n",
        "mouse_button 0\n",
        "mouse_move 1023 767\n",
    ], "correct commands sent";

    $console->activate;
    $console->send_key({key => 'a'});
    $console->send_key({key => 'ctrl-x'});
    $console->type_string({text => "some test\n"});
    $console->disable;
    ok open($cmds_fh, 'input-commands'), 'open input-commands';
    @cmds = <$cmds_fh>;
    is_deeply \@cmds, [
        "a\n",
        "ctrl-x\n",
        "s\n", "o\n", "m\n", "e\n", "spc\n", "t\n", "e\n", "s\n", "t\n", "ret\n",
    ], "correct commands sent";

    $bmwqemu::vars{GENERAL_HW_KEYBOARD_URL} = 'http://127.0.0.42:42000/cmd';

    # mock ua
    my $urls = [];
    my $user_agent_mock = Test::MockModule->new('Mojo::UserAgent');
    my $http = Test::MockModule->new('Mojo::Transaction::HTTP');
    $user_agent_mock->redefine(get => sub ($ua, $url) { push(@$urls, "$url"); Mojo::Transaction::HTTP->new });
    $http->redefine(result => sub { Mojo::Message::Response->new->code(200)->body("hallo") });

    $console->activate;
    $console->send_key({key => 'a'});
    $console->send_key({key => 'ctrl-x'});
    $console->type_string({text => "some test\n"});
    $console->disable;
    is_deeply $urls, [
        'http://127.0.0.42:42000/cmd?sendkey=a',
        'http://127.0.0.42:42000/cmd?sendkey=ctrl-x',
        'http://127.0.0.42:42000/cmd?type=some+test%0A'
    ], "correct kbd emu requests sent";
};

done_testing;

END {
    unlink 'input-commands';
}
