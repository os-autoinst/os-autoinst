#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Mock::Time;
use Test::MockModule 'strict';
use Test::MockObject;
use Test::Output qw(combined_like stderr_like);
use Test::Warnings qw(:all :report_warnings);
use POSIX qw(waitpid _exit);
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use consoles::console;
use backend::baseclass;
use consoles::VNC;
use consoles::s3270;

$bmwqemu::vars{ZVM_HOST} = "localhost";
$bmwqemu::vars{ZVM_GUEST} = "guest";
$bmwqemu::vars{ZVM_PASSWORD} = "password";

my $ipc_run_mock = Test::MockModule->new('IPC::Run');
my $vnc_mock = Test::MockModule->new('consoles::VNC');
my $inet_mock = Test::MockModule->new('IO::Socket::INET');
my $s = Test::MockObject->new->set_true(qw(sockopt fileno print connected close blocking));

$vnc_mock->redefine(_read_socket => sub { substr(${$_[1]}, $_[3], $_[2]) = $s->mocked_read; length ${$_[1]} });
$vnc_mock->redefine(login => 1);
$inet_mock->redefine(new => $s);
$ipc_run_mock->redefine(start => sub ($self, $in, $out, $err) {
        $$out = "success\nconnet(localhost)\nok";
        return bless({'KIDS' => [{'VAL' => $$in, 'PID' => '0', 'NUM' => 1, 'TYPE' => 'cmd', 'RESULT' => 1, 'OPS' => []}]}, 'IPC::Run');
});
$ipc_run_mock->redefine(pump => 1);

my $backend_base = backend::baseclass->new();
my $backend_mock = Test::MockModule->new('backend::baseclass')->redefine(request_screen_update => sub ($self, $args = undef) {
        $self->{cmdpipe} = undef;    # ensure we'll exit the while loop after one iteration
})->redefine('capture_screenshot');

ok my $s3270_console = consoles::s3270->new('s3270', undef), 's3270_console connection can be established';
$s3270_console->{backend} = $backend_base;

subtest 's3270_console start' => sub {
    my $bless_obj = bless({'KIDS' => [{'VAL' => '', 'PID' => '0', 'NUM' => 1, 'TYPE' => 'cmd', 'RESULT' => 1, 'OPS' => []}]}, 'IPC::Run');
    $s3270_console->start();
    is_deeply $s3270_console->{connection}, $bless_obj, 's3270 console can be started';
};

subtest 's3270 send' => sub {
    my $ret = $s3270_console->send_3270("Connect(localhost)", command_status => 'ok');
    is $s3270_console->{in}, "Connect(localhost)\n", 'input command matches';
    is $ret->{terminal_status}, "connet(localhost)", 'terminal status matches';
    is $ret->{command_status}, "ok", 'command status matches';
    is_deeply $ret->{command_output}, ['success'], 'command output matches';
};

done_testing();
