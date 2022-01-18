#!/usr/bin/perl

# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Warnings qw(:all :report_warnings);
use Test::Fatal;
use Test::MockModule;
use Test::MockObject;
use Test::Output qw(stderr_like);
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use consoles::vnc_base;

my $c = consoles::vnc_base->new('sut', {});
is $c->screen, $c, 'screen returns self';
my $vnc = Test::MockObject->new->set_true('map_and_send_key');
$c->{vnc} = $vnc;
$vnc->set_always('socket', 0);
$c->disable;
is $c->{vnc}, undef, 'VNC removed by disable';

is $c->get_last_mouse_set({}), undef, 'can call get_last_mouse_set';
$vnc->set_true('check_vnc_stalls');
is $c->disable_vnc_stalls, undef, 'can call disable_vnc_stalls without VNC';
ok !$vnc->called('check_vnc_stalls'), 'check_vnc_stalls not called without VNC';
$c->{vnc} = $vnc;
is $c->disable_vnc_stalls, 1, 'can call disable_vnc_stalls with VNC';
ok $vnc->called('check_vnc_stalls'), 'check_vnc_stalls called with VNC';
my $vnc_mock = Test::MockModule->new('consoles::VNC');
$vnc_mock->mock(new => $vnc);
$vnc->set_true('login');
stderr_like { $c->connect_remote({hostname => 'localhost', port => 42}) } qr/Establishing VNC connection to localhost:42/, 'can call connect_remote';
$vnc->set_true('update_framebuffer', 'send_update_request');
is $c->request_screen_update, undef, 'can call request_screen_update';
$vnc->set_always('_framebuffer', 0);
$vnc->clear('update_framebuffer');
is $c->current_screen, undef, 'can call current_screen without framebuffer';
$vnc->called_ok('update_framebuffer', 'update_framebuffer called when framebuffer is initialized');
$vnc->set_true('_framebuffer');
ok $c->current_screen, 'can call current_screen with framebuffer';
$c->{backend} = Test::MockObject->new->set_true('run_capture_loop');
ok $c->type_string({max_interval => 1, text => 'foo'}), 'type_string with small max_interval';
my ($name, $args) = $c->{backend}->next_call;
ok 0.5 < (@$args)[-1] && (@$args)[-1] < 0.6, 'seconds per keypress somewhere below 1';
ok $c->send_key({}), 'send_key can be called';
ok $c->hold_key({}), 'hold_key can be called';
ok $c->release_key({}), 'release_key can be called';
$c->{mouse} = Test::MockObject->new;
$c->{mouse}->{x} = $c->{mouse}->{y} = 0;
$vnc->set_always('width', 0);
$vnc->set_true('mouse_move_to');
$vnc->set_always('height', 0);
$vnc->set_always('absolute', 0);
stderr_like { $c->mouse_hide({}) } qr/mouse_move -1, -1/, 'mouse_hide goes to offscreen position';
dies_ok { $c->mouse_set({}) } 'mouse_set needs x/y parameters';
stderr_like { $c->mouse_set({x => 0, y => 0}) } qr/mouse_move 0, 0/, 'mouse_set outputs new mouse position';
ok $vnc->called('mouse_move_to'), 'actually moved to default 0/0 position';
$vnc->clear('mouse_move_to');
ok !$vnc->called('mouse_move_to'), 'mouse_move_to not called for same position';
stderr_like { $c->mouse_set({x => 0, y => 0}) } qr/mouse_move 0, 0/, 'second mouse_set keeps mouse';
ok $vnc->called_ok('mouse_move_to'), 'mouse is moved again';
$vnc->set_true('send_pointer_event');
stderr_like { $c->mouse_button({button => 'left', bstate => 0}) } qr/pointer_event.*0, 0/, 'mouse_button can be called';
stderr_like { $c->mouse_button({button => 'right', bstate => 0}) } qr/0, 0/, 'mouse_button right can be called';
stderr_like { $c->mouse_button({button => 'middle', bstate => 0}) } qr/0, 0/, 'mouse_button middle can be called';

done_testing;
