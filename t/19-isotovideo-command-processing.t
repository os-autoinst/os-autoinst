#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Test::MockModule;
use Test::Warnings;
use OpenQA::Isotovideo::CommandHandler;

BEGIN {
    unshift @INC, '..';
}

# declare fake file descriptors
my $cmd_srv_fd              = 0;
my $backend_fd              = 1;
my $answer_fd               = 2;
my @last_received_msg_by_fd = (undef, undef, undef);

# mock the json rpc
my $rpc_mock = new Test::MockModule('myjsonrpc');
$rpc_mock->mock(send_json => sub {
        my ($fd, $cmd) = @_;
        if (!defined($fd) || ($fd != $cmd_srv_fd && $fd != $backend_fd && $fd != $answer_fd)) {
            fail('invalid file descriptor passed to send_json: ' . ($fd ? $fd : 'undef'));
            return;
        }
        $last_received_msg_by_fd[$fd] = $cmd;
});
$rpc_mock->mock(read_json => sub {
        fail('we do not expect anything to be read here');
});

# setup a CommandHandler instance using the fake file descriptors
my $command_handler = OpenQA::Isotovideo::CommandHandler->new(
    cmd_srv_fd             => $cmd_srv_fd,
    backend_fd             => $backend_fd,
    current_test_name      => 'welcome',
    current_test_full_name => 'installation-welcome',
);

subtest 'report timeout, set pause on assert/check screen timeout' => sub {
    my %basic_report_timeout_cmd = (
        cmd => 'report_timeout',
        msg => 'some test',
    );

    # report timeout when not supposted to pause
    $command_handler->process_command($answer_fd, {
            cmd   => 'is_configured_to_pause_on_timeout',
            check => 0,
    });
    is_deeply($last_received_msg_by_fd[$answer_fd], {ret => 0}, 'not configured to pause on assert_screen');
    $command_handler->process_command($answer_fd, {
            cmd   => 'is_configured_to_pause_on_timeout',
            check => 1,
    });
    is_deeply($last_received_msg_by_fd[$answer_fd], {ret => 0}, 'not configured to pause on check_screen');
    $command_handler->process_command($answer_fd, \%basic_report_timeout_cmd);
    is_deeply($last_received_msg_by_fd[$answer_fd], {ret => 0}, 'not supposed to pause');
    is_deeply($last_received_msg_by_fd[$cmd_srv_fd], undef, 'nothing sent to cmd srv');

    # enable pause on assert_screen timeout
    $command_handler->process_command($answer_fd, {
            cmd  => 'set_pause_on_assert_screen_timeout',
            flag => 1,
    });
    is_deeply($last_received_msg_by_fd[$cmd_srv_fd], {
            set_pause_on_assert_screen_timeout => 1,
    }, 'event passed cmd srv');
    is($command_handler->pause_on_assert_screen_timeout, 1, 'enabling pause on assert_screen timeout');
    $command_handler->process_command($answer_fd, {
            cmd   => 'is_configured_to_pause_on_timeout',
            check => 0,
    });
    is_deeply($last_received_msg_by_fd[$answer_fd], {ret => 1}, 'configured to pause on assert_screen');
    $command_handler->process_command($answer_fd, {
            cmd   => 'is_configured_to_pause_on_timeout',
            check => 1,
    });
    is_deeply($last_received_msg_by_fd[$answer_fd], {ret => 0}, 'not configured to pause on check_screen');

    # report timeout when supposed to pause
    $command_handler->process_command($answer_fd, \%basic_report_timeout_cmd);
    # note: $last_received_msg_by_fd[$answer_fd] does not contain {ret => 1} because answer has
    #       been postponed
    is_deeply($last_received_msg_by_fd[$cmd_srv_fd], {
            paused => \%basic_report_timeout_cmd,
            reason => $basic_report_timeout_cmd{msg},
    }, 'event passed cmd srv');
    is($command_handler->postponed_answer_fd, $answer_fd, 'postponed answer fd set');

    # timeout on check screen still won't pause
    $command_handler->process_command($answer_fd, {%basic_report_timeout_cmd, check => 1});
    is_deeply($last_received_msg_by_fd[$answer_fd], {ret => 0}, 'not supposed to pause on check_screen');

    # enable pause on check_screen timeout
    $command_handler->process_command($answer_fd, {
            cmd  => 'set_pause_on_check_screen_timeout',
            flag => 1,
    });
    is_deeply($last_received_msg_by_fd[$cmd_srv_fd], {
            set_pause_on_check_screen_timeout => 1,
    }, 'event passed cmd srv');
    is($command_handler->pause_on_check_screen_timeout, 1, 'enabling pause on check_screen timeout');
    $command_handler->process_command($answer_fd, {
            cmd   => 'is_configured_to_pause_on_timeout',
            check => 0,
    });
    is_deeply($last_received_msg_by_fd[$answer_fd], {ret => 1}, 'configured to pause on assert_screen');
    $command_handler->process_command($answer_fd, {
            cmd   => 'is_configured_to_pause_on_timeout',
            check => 1,
    });
    is_deeply($last_received_msg_by_fd[$answer_fd], {ret => 1}, 'configured to pause on check_screen');
    $command_handler->process_command($answer_fd, \%basic_report_timeout_cmd);
    is_deeply($last_received_msg_by_fd[$answer_fd], {ret => 1}, 'supposed to pause on check_screen');
};

done_testing;
