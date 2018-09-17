# Copyright © 2018 SUSE LLC
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

package OpenQA::Isotovideo::CommandHandler;

use strict;
use warnings;
use Mojo::Base 'Mojo::EventEmitter';
use Mojo::UserAgent;
use Mojo::URL;
use bmwqemu;
use testapi 'diag';
use OpenQA::Isotovideo::Interface;
use File::stat;
use Try::Tiny;
use POSIX 'strftime';

# io handles for sending data to command server and backend
has [qw(cmd_srv_fd backend_fd answer_fd)] => undef;

# the name of the current test (full name includes category prefix, eg. installation-)
has [qw(current_test_name current_test_full_name)];

# conditions when to pause
has pause_test_name                => sub { $bmwqemu::vars{PAUSE_AT} };
has pause_on_assert_screen_timeout => sub { $bmwqemu::vars{PAUSE_ON_ASSERT_SCREEN_TIMEOUT} // 0 };
has pause_on_check_screen_timeout  => sub { $bmwqemu::vars{PAUSE_ON_CHECK_SCREEN_TIMEOUT} // 0 };

# the reason why the test execution has paused or 0 if not paused
has reason_for_pause => 0;

# when paused, save the command from autotest which has been postponed to be able to resume
has postponed_answer_fd => undef;
has postponed_command   => undef;

# properties consumed by isotovideo::check_asserted_screen
#  * timeout for the select (only set for check_screens)
#  * tags received from 'set_tags_to_assert' command
#  * do not wait for timeout if set
has [qw(timeout no_wait tags)];

# set to the socket we have to send replies to when the backend is done (FIXME: just use answer_fd?)
has backend_requester => undef;

# whether the test has already been completed and whether it has died
has [qw(test_completed test_died)] => 0;

sub clear_tags_and_timeout {
    my ($self) = @_;
    $self->tags(undef);
    $self->timeout(undef);
}

# processes the $response and send the answer back via $answer_fd by invoking one of the subsequent handler methods
# note: To add a new command, create a handler method called "_handle_command_<new_command_name>".
sub process_command {
    my ($self, $answer_fd, $command_to_process) = @_;
    my $cmd = $command_to_process->{cmd} or die 'isotovideo: no command specified';
    $self->answer_fd($answer_fd);

    # invoke handler for the command
    if (my $handler = $self->can('_handle_command_' . $cmd)) {
        return $handler->($self, $command_to_process, $cmd);
    }
    if ($cmd =~ m/^backend_(.*)/) {
        return $self->_pass_command_to_backend_unless_paused($command_to_process, $1);
    }

    die 'isotovideo: unknown command ' . $cmd;
}

sub _postpone_backend_command_until_resumed {
    my ($self, $response) = @_;
    my $cmd             = $response->{cmd};
    my $reson_for_pause = $self->reason_for_pause;
    return unless $reson_for_pause;

    # emit info
    $self->_send_to_cmd_srv({paused => $response, reason => $reson_for_pause});
    diag("isotovideo: paused, so not passing $cmd to backend");

    # postpone execution of command
    $self->postponed_answer_fd($self->answer_fd);
    $self->postponed_command($response);

    # send no reply to autotest, just let it wait
    return 1;
}

sub _send_to_cmd_srv {
    my ($self, $data) = @_;
    myjsonrpc::send_json($self->cmd_srv_fd, $data);
}

sub _send_to_backend {
    my ($self, $data) = @_;
    myjsonrpc::send_json($self->backend_fd, $data);
}

sub send_to_backend_requester {
    my ($self, $data) = @_;
    myjsonrpc::send_json($self->backend_requester, $data);
    $self->backend_requester(undef);
}

sub _respond {
    my ($self, $data) = @_;
    myjsonrpc::send_json($self->answer_fd, $data);
}

sub _respond_ok {
    my ($self) = @_;
    $self->_respond({ret => 1});
}

sub _pass_command_to_backend_unless_paused {
    my ($self, $response, $backend_cmd) = @_;
    return if $self->_postpone_backend_command_until_resumed($response);

    die 'isotovideo: we need to implement a backend queue' if $self->backend_requester;
    $self->backend_requester($self->answer_fd);

    $self->_send_to_cmd_srv({$backend_cmd => $response});
    $self->_send_to_backend({cmd => $backend_cmd, arguments => $response});
}

sub _handle_command_report_timeout {
    my ($self, $response) = @_;

    my $supposed_to_pause
      = $self->pause_on_check_screen_timeout || ($self->pause_on_assert_screen_timeout && !$response->{check});
    if (!$supposed_to_pause) {
        $self->_respond({ret => 0});
        return;
    }

    my $reason_for_pause = $response->{msg};
    $self->reason_for_pause($reason_for_pause);
    $self->_send_to_cmd_srv({paused => $response, reason => $reason_for_pause});
    diag('isotovideo: pausing test execution on timeout as requested at ' . $self->current_test_full_name);

    # postpone sending the reply
    $self->postponed_answer_fd($self->answer_fd);
    $self->postponed_command(undef);
}

sub _handle_command_set_pause_at_test {
    my ($self, $response) = @_;
    my $pause_test_name = $response->{name};

    diag('isotovideo: test execution will be paused at test ' . $pause_test_name);
    $self->pause_test_name($pause_test_name);
    $self->_send_to_cmd_srv({set_pause_at_test => $pause_test_name});
    $self->_respond_ok();
}

sub _handle_command_set_pause_on_assert_screen_timeout {
    my ($self, $response) = @_;
    my $pause_on_assert_screen_timeout = $response->{flag};

    $self->pause_on_assert_screen_timeout($pause_on_assert_screen_timeout);
    $self->_send_to_cmd_srv({set_pause_on_assert_screen_timeout => $pause_on_assert_screen_timeout});
    $self->_respond_ok();
}

sub _handle_command_set_pause_on_check_screen_timeout {
    my ($self, $response) = @_;
    my $pause_on_check_screen_timeout = $response->{flag};

    $self->pause_on_check_screen_timeout($pause_on_check_screen_timeout);
    $self->_send_to_cmd_srv({set_pause_on_check_screen_timeout => $pause_on_check_screen_timeout});
    $self->_respond_ok();
}

sub _handle_command_resume_test_execution {
    my ($self, $response) = @_;
    my $postponed_command   = $self->postponed_command;
    my $postponed_answer_fd = $self->postponed_answer_fd;

    diag($self->reason_for_pause ?
          'isotovideo: test execution will be resumed'
        : 'isotovideo: resuming test execution requested but not paused anyways'
    );
    $self->_send_to_cmd_srv({resume_test_execution => $postponed_command});

    # unset paused state to continue passing commands to backend
    $self->reason_for_pause(0);

    # download new needles
    my @files_to_download;
    my $needle_dir   = needle::default_needle_dir();
    my $new_needles  = $response->{new_needles} // [];
    my $openqa_url   = 'http://' . $bmwqemu::vars{OPENQA_URL};
    my $add_download = sub {
        my ($needle, $extension, $path_param) = @_;
        my $needle_name     = $needle->{name};
        my $latest_update   = $needle->{t_updated};
        my $download_target = "$needle_dir/$needle_name.$extension";
        if (my $target_stat = stat($download_target)) {
            if (my $target_last_modified = $target_stat->[9] // $target_stat->[8]) {
                $target_last_modified = strftime('%Y-%m-%dT%H:%M:%SZ', gmtime($target_last_modified));
                if ($target_last_modified >= $latest_update) {
                    diag("skip downloading new needle: $download_target seems already up-to-date (last update: $target_last_modified > $latest_update)");
                    return;
                }
            }
        }
        push(@files_to_download, {
                target => $download_target,
                url    => Mojo::URL->new($openqa_url . $needle->{$path_param}),
        });
    };
    for my $needle (@$new_needles) {
        $add_download->($needle, 'json', 'json_path');
        $add_download->($needle, 'png',  'image_path');
    }
    my $ua = Mojo::UserAgent->new;
    for my $download (@files_to_download) {
        my $download_url    = $download->{url};
        my $download_target = $download->{target};
        diag("download new needle: $download_url => $download_target");

        my $download_res = $ua->get($download_url)->result;
        if (!$download_res->is_success) {
            diag("failed to download needle: $download_url");
            next;
        }
        try {
            unlink($download_target);
            Mojo::File->new($download_target)->spurt($download_res->body);
        }
        catch {
            diag("unable to store download under $download_target");
        };
    }

    # if no command has been postponed (because paused due to timeout) just return 1
    if (!$postponed_command) {
        myjsonrpc::send_json($postponed_answer_fd, {ret => 1});
        $self->postponed_answer_fd(undef);
        return;
    }

    # resume with postponed command so autotest can continue
    my $cmd = $postponed_command->{cmd};
    diag("isotovideo: resuming, continue passing $cmd to backend");

    $self->postponed_command(undef);
    $self->postponed_answer_fd(undef);
    $self->process_command($postponed_answer_fd, $postponed_command);
}

sub _handle_command_set_current_test {
    my ($self, $response) = @_;

    # FIXME: why set_serial_offset here?
    $bmwqemu::backend->_send_json({cmd => 'set_serial_offset'});

    my ($test_name, $full_test_name) = ($response->{name}, $response->{full_name});
    my $pause_test_name = $self->pause_test_name;
    $self->current_test_name($test_name);
    $self->current_test_full_name($full_test_name);
    $self->_send_to_cmd_srv({
            set_current_test       => $test_name,
            current_test_full_name => $full_test_name,
    });

    if ($pause_test_name
        && $test_name
        && $full_test_name
        && ($pause_test_name eq $test_name || $pause_test_name eq $full_test_name))
    {
        diag("isotovideo: pausing test execution of $pause_test_name because we're supposed to pause at this test module");
        $self->reason_for_pause('reached module ' . $pause_test_name);
    }
    $self->_respond_ok();
}

sub _handle_command_tests_done {
    my ($self, $response) = @_;

    $self->test_died($response->{died});
    $self->test_completed($response->{completed});
    $self->emit(tests_done => $response);
}

sub _handle_command_check_screen {
    my ($self, $response) = @_;
    $self->no_wait($response->{no_wait} // 0);
    return if $self->_postpone_backend_command_until_resumed($response);

    $self->_send_to_cmd_srv({check_screen => $response->{mustmatch}});
    $self->tags($bmwqemu::backend->_send_json(
            {
                cmd       => 'set_tags_to_assert',
                arguments => {
                    mustmatch => $response->{mustmatch},
                    timeout   => $response->{timeout},
                    check     => $response->{check},
                },
            })->{tags});
}

sub _handle_command_status {
    my ($self, $response) = @_;
    $self->_respond({
            tags                           => $self->tags,
            running                        => $self->current_test_name,
            current_test_full_name         => $self->current_test_full_name,
            pause_test_name                => $self->pause_test_name,
            pause_on_assert_screen_timeout => $self->pause_on_assert_screen_timeout,
            pause_on_check_screen_timeout  => $self->pause_on_check_screen_timeout,
            test_execution_paused          => $self->reason_for_pause,
    });
}

sub _handle_command_version {
    my ($self, $response) = @_;
    $self->_respond({
            test_git_hash    => $bmwqemu::vars{TEST_GIT_HASH},
            needles_git_hash => $bmwqemu::vars{NEEDLES_GIT_HASH},
            version          => $OpenQA::Isotovideo::Interface::version,
    });
}

sub _handle_command_read_serial {
    my ($self, $response) = @_;

    # This will stop to work if we change the serialfile after the initialization because of the fork
    my ($serial, $pos) = $bmwqemu::backend->{backend}->read_serial($response->{position});
    $self->_respond({serial => $serial, position => $pos});
}

sub _handle_command_send_clients {
    my ($self, $response) = @_;
    delete $response->{cmd};
    delete $response->{json_cmd_token};
    $self->_send_to_cmd_srv($response);
    $self->_respond_ok();
}

1;
