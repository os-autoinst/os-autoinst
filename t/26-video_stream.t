#!/usr/bin/perl
# Copyright 2021 Marek Marczykowski-Górecki
# Copyright 2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;
use Mojo::UserAgent;
use Mojo::Transaction::HTTP;
use Test::Warnings qw(:all :report_warnings);
use File::Basename;
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
        return $v4l2_ctl_results{$_[1]} || $v4l2_ctl_results{''};
});
my $mock_video_source = '/dev/null';
$mock_console->redefine(_get_ffmpeg_cmd => sub ($self, $url) {
        my @cmd = ('cat', $mock_video_source);
        return \@cmd;
});

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
    is_deeply \@v4l2_ctl_calls, [[('/dev/video0', '--get-dv-timings')]], "calls to v4l2-ctl";

    @v4l2_ctl_calls = ();
    # no input connected
    %v4l2_ctl_results = ('--get-dv-timings' => '0x0pnan');
    $console->connect_remote({url => '/dev/video0'});
    is $console->{dv_timings_supported}, 1, "use v4l2-ctl";
    is $console->{dv_timings}, '', "correct lack of resolution";
    is_deeply \@v4l2_ctl_calls, [
        [('/dev/video0', '--get-dv-timings')],
        [('/dev/video0', '--set-dv-bt-timings query')],
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
        [('/dev/video0', '--get-dv-timings')],
        [('/dev/video0', '--set-dv-bt-timings query')],
        [('/dev/video0', '--get-dv-timings')],
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
        [('/dev/video0', '--set-edid type=hdmi')],
        [('/dev/video0', '--get-dv-timings')],
        [('/dev/video0', '--set-dv-bt-timings query')],
        [('/dev/video0', '--get-dv-timings')],
    ], "calls to v4l2-ctl";

};

subtest 'frames parsing' => sub {
    my ($img, $received_img);
    my $console = consoles::video_stream->new(undef, {url => 'udp://@:5004'});
    $mock_video_source = $data_dir . "frame1.ppm";
    $console->activate;

    $img = tinycv::read($data_dir . "frame1.png");
    $received_img = $console->current_screen();
    is $received_img->similarity($img), 1_000_000, "received correct frame";
    $console->disable_video;

    # now two frames
    $mock_video_source = $data_dir . "frames12.ppm";
    $console->connect_remote({url => 'udp://@:5004'});

    $img = tinycv::read($data_dir . "frame2.png");
    $received_img = $console->current_screen();
    is $received_img->similarity($img), 1_000_000, "received correct frame";
    $console->disable_video;
};

subtest 'v4l2 resolution' => sub {
    $mock_video_source = $data_dir . "frame1.ppm";
    my $console = consoles::video_stream->new(undef, {url => '/dev/video0'});
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
        [('/dev/video0', '--query-dv-timings')],
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
        [('/dev/video0', '--query-dv-timings')],
        [('/dev/video0', '--set-dv-bt-timings query')],
        [('/dev/video0', '--get-dv-timings')],
    ], "calls to v4l2-ctl";
    $console->disable_video;
};

subtest 'input events' => sub {
    my ($cmds_fh, @cmds);
    my $console = consoles::video_stream->new(undef, {
            url => 'udp://@:5004',
            input_cmd => 'cat > input-commands',
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
