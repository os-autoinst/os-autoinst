#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;

use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use Test::MockModule;
use Test::Output qw(stderr_like stderr_unlike combined_like);
use Test::Warnings ':report_warnings';
use Test::Fatal;
use Mojo::JSON;
use OpenQA::Isotovideo::CommandHandler;
use OpenQA::Isotovideo::Interface;
use OpenQA::Isotovideo::Runner;

# declare fake file descriptors
my $cmd_srv_fd = 0;
my $backend_fd = 1;
my $answer_fd = 2;
my @last_received_msg_by_fd = (undef, undef, undef);

# mock the json rpc
my $rpc_mock = Test::MockModule->new('myjsonrpc');
$rpc_mock->redefine(send_json => sub {
        my ($fd, $cmd) = @_;
        if (!defined($fd) || ($fd != $cmd_srv_fd && $fd != $backend_fd && $fd != $answer_fd)) {
            fail('invalid file descriptor passed to send_json: ' . ($fd ? $fd : 'undef'));    # uncoverable statement
            return;    # uncoverable statement
        }
        $last_received_msg_by_fd[$fd] = $cmd;
});
$rpc_mock->redefine(read_json => sub {
        fail('we do not expect anything to be read here');    # uncoverable statement
});

# mock bmwqemu/backend
{
    package FakeBackend;    # uncoverable statement
    sub new ($class) { bless({messages => []}, $class) }
    sub _send_json ($self, $cmd) {
        push(@{$self->{messages}}, $cmd);
        return $cmd->{cmd} eq 'is_shutdown' ? 'down' : {tags => [qw(some fake tags)]};
    }
    sub stop { die "faking stop\n" }
}
{
    package bmwqemu;
    our $backend = FakeBackend->new();
}

# setup a CommandHandler instance using the fake file descriptors
my $command_handler = OpenQA::Isotovideo::CommandHandler->new(
    cmd_srv_fd => $cmd_srv_fd,
    backend_fd => $backend_fd,
    current_test_name => 'welcome',
    status => 'initial',
);

sub reset_state () {
    $command_handler->tags(undef);
    $command_handler->pause_test_name(undef);
    $last_received_msg_by_fd[$answer_fd] = undef;
    $last_received_msg_by_fd[$cmd_srv_fd] = undef;
}

subtest set_current_test => sub {
    $command_handler->process_command($answer_fd, {
            cmd => 'set_current_test',
            name => 'welcome',
            full_name => 'installation-welcome',
    });
    is($command_handler->status, 'running', 'Status == running');
};


subtest status => sub {
    $command_handler->tags([qw(foo bar)]);
    $command_handler->pause_test_name('foo');
    $command_handler->process_command($answer_fd, {cmd => 'status'});
    is_deeply($last_received_msg_by_fd[$answer_fd], {
            tags => [qw(foo bar)],
            running => 'welcome',
            current_test_full_name => 'installation-welcome',
            current_api_function => undef,
            pause_test_name => 'foo',
            pause_on_screen_mismatch => Mojo::JSON->false,
            pause_on_next_command => 0,
            pause_on_failure => 0,
            test_execution_paused => 0,
            devel_mode_major_version => $OpenQA::Isotovideo::Interface::developer_mode_major_version,
            devel_mode_minor_version => $OpenQA::Isotovideo::Interface::developer_mode_minor_version,
    }, 'status returned as expected');
};

subtest 'set pause at test' => sub {
    reset_state;

    stderr_like {
        $command_handler->process_command($answer_fd, {cmd => 'set_pause_at_test', name => 'some test'})
    } qr/paused.*some test/, 'log for pause';
    is_deeply($last_received_msg_by_fd[$answer_fd], {ret => 1}, 'answer received');
    is_deeply($last_received_msg_by_fd[$cmd_srv_fd], {set_pause_at_test => 'some test'}, 'broadcasted via command server');
    is($command_handler->pause_test_name, 'some test', 'test to pause at set');

    stderr_unlike {
        $command_handler->process_command($answer_fd, {cmd => 'set_current_test', name => 'foo', full_name => 'foo'})
    } qr/pausing/, 'pausing not logged';
    is_deeply $last_received_msg_by_fd[$answer_fd], {ret => 1}, 'not paused on different test module';
    ok !$command_handler->reason_for_pause, 'reason for pause set not set';
    is $command_handler->postponed_answer_fd, undef, 'answer not postponed';

    stderr_like {
        $command_handler->process_command($answer_fd, {cmd => 'set_current_test', name => 'some test', full_name => 'some test'})
    } qr/pausing test execution.*some test/, 'pausing logged';
    is $command_handler->reason_for_pause, 'reached module some test', 'reason for pause set when reaching module to pause on';
    is $command_handler->postponed_answer_fd, $answer_fd, 'answer postponed';

    stderr_like {
        $command_handler->process_command($answer_fd, {cmd => 'set_pause_at_test', name => undef});
    } qr/no longer.*paused/, 'log for unpause';
    is_deeply($last_received_msg_by_fd[$answer_fd], {ret => 1}, 'answer received');
    is_deeply($last_received_msg_by_fd[$cmd_srv_fd], {set_pause_at_test => undef}, 'broadcasted via command server');
    is($command_handler->pause_test_name, undef, 'test to pause at unset');
};

subtest 'report timeout, set pause on assert/check screen timeout' => sub {
    my %basic_report_timeout_cmd = (cmd => 'report_timeout', msg => 'some test');
    reset_state;

    # report timeout when not supposted to pause
    $command_handler->process_command($answer_fd, {cmd => 'is_configured_to_pause_on_timeout', check => 0});
    is_deeply($last_received_msg_by_fd[$answer_fd], {ret => 0}, 'not configured to pause on assert_screen');
    $command_handler->process_command($answer_fd, {cmd => 'is_configured_to_pause_on_timeout', check => 1});
    is_deeply($last_received_msg_by_fd[$answer_fd], {ret => 0}, 'not configured to pause on check_screen');
    $command_handler->process_command($answer_fd, \%basic_report_timeout_cmd);
    is_deeply($last_received_msg_by_fd[$answer_fd], {ret => 0}, 'not supposed to pause');
    is_deeply($last_received_msg_by_fd[$cmd_srv_fd], undef, 'nothing sent to cmd srv');

    # enable pause on assert_screen timeout
    $command_handler->process_command($answer_fd, {cmd => 'set_pause_on_screen_mismatch', pause_on => 'assert_screen'});
    is_deeply($last_received_msg_by_fd[$cmd_srv_fd], {
            set_pause_on_screen_mismatch => 'assert_screen',
    }, 'event passed cmd srv');
    is($command_handler->pause_on_screen_mismatch, 'assert_screen', 'enabling pause on assert_screen timeout');
    $command_handler->process_command($answer_fd, {cmd => 'is_configured_to_pause_on_timeout', check => 0});
    is_deeply($last_received_msg_by_fd[$answer_fd], {ret => 1}, 'configured to pause on assert_screen');
    $command_handler->process_command($answer_fd, {cmd => 'is_configured_to_pause_on_timeout', check => 1});
    is_deeply($last_received_msg_by_fd[$answer_fd], {ret => 0}, 'not configured to pause on check_screen');

    # report timeout when supposed to pause
    stderr_like {
        $command_handler->process_command($answer_fd, \%basic_report_timeout_cmd);
    } qr/pausing.*on timeout/, 'log pause on timeout';
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
    $command_handler->process_command($answer_fd, {cmd => 'set_pause_on_screen_mismatch', pause_on => 'check_screen'});
    is_deeply($last_received_msg_by_fd[$cmd_srv_fd], {
            set_pause_on_screen_mismatch => 'check_screen',
    }, 'event passed cmd srv');
    is($command_handler->pause_on_screen_mismatch, 'check_screen', 'enabling pause on check_screen timeout');
    $command_handler->process_command($answer_fd, {cmd => 'is_configured_to_pause_on_timeout', check => 0});
    is_deeply($last_received_msg_by_fd[$answer_fd], {ret => 1}, 'configured to pause on assert_screen');
    $command_handler->process_command($answer_fd, {cmd => 'is_configured_to_pause_on_timeout', check => 1});
    is_deeply($last_received_msg_by_fd[$answer_fd], {ret => 1}, 'configured to pause on check_screen');
    stderr_like {
        $command_handler->process_command($answer_fd, \%basic_report_timeout_cmd);
    } qr/pausing.*on timeout/, 'log pause on timeout';
    is_deeply($last_received_msg_by_fd[$answer_fd], {ret => 1}, 'supposed to pause on check_screen');

    # disabling pause on assert_screen timeout disables pause on check_screen timeout as well
    $command_handler->process_command($answer_fd, {cmd => 'set_pause_on_screen_mismatch', pause_on => undef});
    is_deeply($last_received_msg_by_fd[$cmd_srv_fd], {
            set_pause_on_screen_mismatch => 0,
    }, 'event passed cmd srv');
    is($command_handler->pause_on_screen_mismatch, undef, 'pause on assert_screen/check_screen timeout disabled');

    $command_handler->reason_for_pause(undef);
};

subtest 'set_pause_on_next_command, postponing command, resuming' => sub {
    # enable pausing on next command
    is($command_handler->pause_on_next_command, 0, 'pause on next command disabled by default');
    $command_handler->process_command($answer_fd, {cmd => 'set_pause_on_next_command', flag => 1});
    is_deeply($last_received_msg_by_fd[$cmd_srv_fd], {
            set_pause_on_next_command => 1,
    }, 'event passed cmd srv');
    is($command_handler->pause_on_next_command, 1, 'pause on next command enabled');

    # check whether the next command gets postponed and the test paused
    stderr_like {
        $command_handler->process_command($answer_fd, {cmd => 'check_screen'});
    } qr/paused,.*not passing check_screen/, 'log on pause before check_screen';
    is_deeply($last_received_msg_by_fd[$cmd_srv_fd], {
            paused => {cmd => 'check_screen'},
            reason => 'reached check_screen and pause on next command enabled',
    }, 'check_screen postponed');
    is_deeply($command_handler->postponed_command, {cmd => 'check_screen'}, 'postponed command set');
    is($command_handler->postponed_answer_fd, $answer_fd, 'answer fd for postponed command set');

    # disable pausing on next command again
    $command_handler->process_command($answer_fd, {cmd => 'set_pause_on_next_command', flag => 0});
    is_deeply($last_received_msg_by_fd[$cmd_srv_fd], {
            set_pause_on_next_command => 0,
    }, 'event passed cmd srv');
    is($command_handler->pause_on_next_command, 0, 'pause on next command disabled');

    # resume postponed command
    stderr_like {
        $command_handler->process_command($answer_fd, {cmd => 'resume_test_execution'});
    } qr/resuming, continue/, 'log on resuming';
    is_deeply($last_received_msg_by_fd[$cmd_srv_fd], {
            check_screen => {
                check => undef,
                mustmatch => undef,
                timeout => undef,
            },
            current_api_function => 'assert_screen',
    }, 'check_screen resumed');
    is($command_handler->postponed_command, undef, 'no command postponed anymore');
    is($command_handler->postponed_answer_fd, undef, 'postponed answer_fd cleared');
    is($command_handler->reason_for_pause, 0, 'test no longer paused');

    # resume without previously postponed command
    # note: The check for relevant early return is provided by mock function of send_json which is defined
    #       at the top of this file.
    stderr_like {
        $command_handler->process_command($answer_fd, {cmd => 'resume_test_execution'});
    } qr/resuming.*not paused anyways/, 'resuming test execution without previously pausing';

    subtest 'resume when no command was postponed but with existing postponed_answer_fd' => sub {
        my $mock = Test::MockModule->new('OpenQA::Isotovideo::CommandHandler');
        $mock->redefine(postponed_command => undef);
        my @set_answer_fd;
        $mock->redefine(postponed_answer_fd => sub ($self, $fd = undef) { push @set_answer_fd, $fd; 1 });
        stderr_unlike {
            $command_handler->process_command($answer_fd, {cmd => 'resume_test_execution'});
        } qr/resuming, continue/, 'Correct output';
        is_deeply($last_received_msg_by_fd[$backend_fd], {
                new_needles => undef,
                ret => 1,
        }, 'Correct data received');
        is_deeply(\@set_answer_fd, [undef, undef]);
    };

};

subtest 'set_pause_on_failure' => sub {
    # enable pausing on failure
    is $command_handler->pause_on_failure, 0, 'pause on failure disabled by default';
    $command_handler->process_command($answer_fd, {cmd => 'set_pause_on_failure', flag => 1});
    is_deeply $last_received_msg_by_fd[$cmd_srv_fd], {set_pause_on_failure => 1}, 'event passed cmd srv (1)';
    is $command_handler->pause_on_failure, 1, 'pause on failure enabled';

    # check whether pausing the test execution on a failure would cause the test to pause now
    $command_handler->process_command($answer_fd, {cmd => 'pause_test_execution', due_to_failure => 1});
    is $command_handler->reason_for_pause, 'manually paused', 'test execution paused due to failure if enabled';
    $command_handler->reason_for_pause(undef);

    # disable pausing on failure
    $command_handler->process_command($answer_fd, {cmd => 'set_pause_on_failure', flag => 0});
    is_deeply $last_received_msg_by_fd[$cmd_srv_fd], {set_pause_on_failure => 0}, 'event passed cmd srv (2)';
    is $command_handler->pause_on_failure, 0, 'pause on failure disabled';

    # check whether pausing the test execution on a failure would *not* cause the test to pause anymore
    $command_handler->process_command($answer_fd, {cmd => 'pause_test_execution', due_to_failure => 1});
    is $command_handler->reason_for_pause, undef, 'test execution not paused due to failure if disabled';
};

subtest 'assert_screen' => sub {
    my %args = (
        mustmatch => [qw(foo bar)],
        timeout => 25,
        check => 0,
    );
    $command_handler->process_command($answer_fd, {cmd => 'check_screen', %args});
    is_deeply($last_received_msg_by_fd[$cmd_srv_fd], {
            check_screen => \%args,
            current_api_function => 'assert_screen',
    }, 'response for assert_screen');
    is_deeply($bmwqemu::backend->{messages}->[-1], {
            cmd => 'set_tags_to_assert',
            arguments => \%args,
    }, 'set_tags_to_assert passed to backend');
    is_deeply($command_handler->tags, [qw(some fake tags)], 'tags assigned');
    is($command_handler->current_api_function, 'assert_screen');
};

subtest 'check_screen' => sub {
    my %args = (
        mustmatch => [qw(foo bar)],
        timeout => 25,
        check => 1,
    );
    $command_handler->process_command($answer_fd, {cmd => 'check_screen', %args});
    is_deeply($last_received_msg_by_fd[$cmd_srv_fd], {
            check_screen => \%args,
            current_api_function => 'check_screen',
    }, 'response for check_screen');
    is_deeply($bmwqemu::backend->{messages}->[-1], {
            cmd => 'set_tags_to_assert',
            arguments => \%args,
    }, 'set_tags_to_assert passed to backend');
    is($command_handler->current_api_function, 'check_screen');
};

subtest 'set_assert_screen_timeout' => sub {
    $command_handler->process_command($answer_fd, {
            cmd => 'set_assert_screen_timeout',
            timeout => 43,
    });
    is_deeply($last_received_msg_by_fd[$cmd_srv_fd], {
            set_assert_screen_timeout => 43,
    }, 'response for set_assert_screen_timeout');
    is_deeply($bmwqemu::backend->{messages}->[-1], {
            cmd => 'set_assert_screen_timeout',
            arguments => 43,
    }, 'timeout passed to backend');
    is_deeply($last_received_msg_by_fd[$answer_fd], {ret => 1}, 'response for set_assert_screen_timeout');
};

subtest version => sub {
    local $bmwqemu::vars{TEST_GIT_HASH} = 'coffee';
    local $bmwqemu::vars{NEEDLES_GIT_HASH} = 'coffee';
    $command_handler->process_command($answer_fd, {
            cmd => 'version',
    });
    is_deeply($last_received_msg_by_fd[$answer_fd], {
            version => $OpenQA::Isotovideo::Interface::version,
            test_git_hash => 'coffee',
            needles_git_hash => 'coffee',
    }, 'response for version');
};

subtest 'send_clients' => sub {
    $command_handler->process_command($answer_fd, {
            cmd => 'send_clients',
            set_current_test => 'FOO',
            current_test_full_name => 'FOO/BAR',
    });
    is_deeply($last_received_msg_by_fd[$cmd_srv_fd], {
            set_current_test => 'FOO',
            current_test_full_name => 'FOO/BAR',
    }, 'response for send_clients');
};

subtest 'invalid command' => sub {
    like exception {
        $command_handler->process_command($answer_fd, {
                cmd => 'foobar',
                lala => 23,
        });
    }, qr{isotovideo: unknown command foobar}, 'Correct error message for unknown command';
};

subtest '_is_configured_to_pause_on_timeout' => sub {
    my $mock = Test::MockModule->new('OpenQA::Isotovideo::CommandHandler');
    $mock->redefine(pause_on_screen_mismatch => 'foo');
    my $result = $command_handler->_is_configured_to_pause_on_timeout({});
    is $result, 0, '_is_configured_to_pause_on_timeout returned 0';
};

subtest check_asserted_screen => sub {
    $command_handler->check_asserted_screen;
    ok($command_handler->timeout, 'Timeout was set');
};

subtest signalhandler => sub {
    my $last_signal;
    my $runner = OpenQA::Isotovideo::Runner->new;
    $runner->command_handler($command_handler);
    $command_handler->once(signal => sub ($event, $sig) { $last_signal = $sig });
    $runner->loop(1);
    stderr_like {
        $runner->_signal_handler('TERM');
    } qr/isotovideo received signal TERM/, 'Signal logged';
    is($runner->loop, 0, 'Loop was stopped');
    is($last_signal, undef, 'No event emitted');

    stderr_like {
        $runner->_signal_handler('INT');
    } qr/isotovideo received signal INT/, 'Signal logged';
    is($last_signal, 'INT', 'Event emitted');
};

subtest 'No readable JSON' => sub {
    my $runner = OpenQA::Isotovideo::Runner->new;
    $runner->command_handler($command_handler);
    # We need valid fd's so fileno works but they're never used
    open(my $readable, "$Bin");
    $runner->testfd($readable);
    $runner->cmd_srv_fd($readable);
    stderr_like {
        $runner->_read_response(undef, $readable);
    } qr/THERE IS NOTHING TO READ/, 'no response';
    is($runner->loop, 0, 'Loop was stopped');
};

subtest 'shutdown handling' => sub {
    my $runner = OpenQA::Isotovideo::Runner->new;
    my $return_code = 1;
    ok !$runner->handle_shutdown(\$return_code), 'handling skipped if $return_code already set';

    combined_like {
        $return_code = 0;
        is $runner->handle_shutdown(\$return_code), 'down', 'backup shutdown state returned';
    } qr/state: down.*unable to stop VM: faking stop/s, 'shutdown state and error to stop VM logged';
    is $return_code, 1, 'return code set to 1 due to error';
};

done_testing;

END {
    unlink OpenQA::Isotovideo::CommandHandler::AUTOINST_STATUSFILE;
    unlink bmwqemu::STATE_FILE;
}
