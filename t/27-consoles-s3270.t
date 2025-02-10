#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Mock::Time;
use Test::MockModule 'strict';
use Test::MockObject;
use Test::Warnings qw(:report_warnings warnings);
use Test::Output qw(combined_like stdout_like);
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use backend::baseclass;
use consoles::s3270;

$bmwqemu::vars{ZVM_HOST} = "localhost.localdomain";
$bmwqemu::vars{ZVM_GUEST} = "guest.user";
$bmwqemu::vars{ZVM_PASSWORD} = "password";

my $ipc_run_mock = Test::MockModule->new('IPC::Run');
my $vnc_mock = Test::MockModule->new('consoles::VNC');
my $localXvnc_mock = Test::MockModule->new('consoles::localXvnc');
my $inet_mock = Test::MockModule->new('IO::Socket::INET');
my $socket_mock = Test::MockObject->new->set_true(qw(sockopt fileno print connected close blocking));

$localXvnc_mock->redefine(activate => sub ($self) { $self->{DISPLAY} = "display" });
$vnc_mock->redefine(_read_socket => sub { substr(${$_[1]}, $_[3], $_[2]) = $socket_mock->mocked_read; length ${$_[1]} });
$vnc_mock->redefine(login => 1);
$inet_mock->redefine(new => $socket_mock);
$ipc_run_mock->redefine(pump => 1);

ok my $s3270_console = consoles::s3270->new('consoles::s3270', undef), 's3270_console connection can be established';
$s3270_console->{backend} = backend::baseclass->new();

subtest 's3270_console start' => sub {
    my $bless_obj = bless({KIDS => [{VAL => '', PID => '0', NUM => 1, TYPE => 'cmd', RESULT => 1, OPS => []}]}, 'IPC::Run');
    $ipc_run_mock->redefine(start => sub ($self, $in, $out, $err) {
            $$out = "success\nconnet($bmwqemu::vars{ZVM_HOST})\nstart to execute process\nok";
            return $bless_obj;
    });
    $s3270_console->start();
    is_deeply $s3270_console->{connection}, $bless_obj, 's3270 console can be started';
};

subtest 's3270 send' => sub {
    my $ret = $s3270_console->send_3270("Connect($bmwqemu::vars{ZVM_HOST})", command_status => 'ok');
    is $s3270_console->{in}, "Connect($bmwqemu::vars{ZVM_HOST})\n", 'input command matches';
    is $ret->{terminal_status}, "start to execute process", 'terminal status matches';
    is $ret->{command_status}, "ok", 'command status matches';
    is_deeply $ret->{command_output}, ['success', "connet($bmwqemu::vars{ZVM_HOST})"], 'command output matches';

    $s3270_console->{out} = "success\nconnet($bmwqemu::vars{ZVM_HOST})\nstart to execute process\nok";
    throws_ok {
        $s3270_console->send_3270("Connect($bmwqemu::vars{ZVM_HOST})", command_status => 'error')
    } qr/expected command exit.*\n.*/, 'exit status not matching, dies';
};

subtest 's3270_console activate' => sub {
    my $count = 0;
    my $s3270_console_mock = Test::MockModule->new('consoles::s3270');
    $s3270_console_mock->redefine(expect_3270 => sub ($self, %arg) {
            $count += 1;
            return ['Fill in your USERID and PASSWORD and press ENTER'] if %arg == 0;
            return ['RECONNECT'] if keys %arg == 1 && exists $arg{buffer_ready} && $count == 2;
            return ['CONNECT'] if keys %arg == 1 && exists $arg{buffer_ready} && $count == 4;
    });
    $s3270_console_mock->redefine(send_3270 => sub ($self, $command = '', %arg) {
            return {'command_output' => ['success'], 'command_status' => 'ok', 'terminal_status' => "Connection to C($bmwqemu::vars{ZVM_HOST}) OK"} if $command =~ /Wait\([1-9],Output\)/;
            return {'command_status' => 'any', 'terminal_status' => "Connection to C($bmwqemu::vars{ZVM_HOST}) OK"};
    });
    cmp_deeply(
        [warnings { $s3270_console->activate(); }],
        bag(
            re(qr/connect_and_login.*\nRECONNECT.*\n/), re(qr/trying hard shutdown and reconnect.*/),
        ), 'reconnect attempt',
    );
};

subtest 's3270_console connect_and_login' => sub {
    my $count = 0;
    my $s3270_console_mock = Test::MockModule->new('consoles::s3270');
    $s3270_console_mock->redefine(send_3270 => sub ($self, $command = '', %arg) {
            return {terminal_status => "Connection to C($bmwqemu::vars{ZVM_HOST}) OK"} if $command =~ /Connect\(\w.+\)/;
    });
    $s3270_console_mock->redefine(expect_3270 => sub ($self, %arg) {
            return ['Fill in your USERID and PASSWORD and press ENTER'] unless keys %arg == 1 && exists $arg{buffer_ready};
            my $return_lines;
            $return_lines = ['RECONNECT'] if $count == 0;
            $return_lines = ['CONNECTED'] if $count == 1;
            $count += 1;
            return $return_lines;
    });
    cmp_deeply(
        [warnings { $s3270_console->connect_and_login(); }],
        bag(
            re(qr/connect_and_login.*\nRECONNECT.*\n/), re(qr/trying hard shutdown and reconnect.*/),
        ), 'reconnect attempt',
    );

    $s3270_console_mock->redefine(expect_3270 => sub ($self, %arg) {
            return ['Fill in your USERID and PASSWORD and press ENTER'] unless keys %arg == 1 && exists $arg{buffer_ready};
            return ['RECONNECT'];
    });
    cmp_deeply(
        [warnings { throws_ok { $s3270_console->connect_and_login() } qr/Could not reclaim.*\n.*/, 'dies' }],
        bag(
            re(qr/connect_and_login.*\nRECONNECT/),
            re(qr/trying hard shutdown and reconnect/),
            re(qr/trying hard shutdown and reconnect/),
            re(qr/connect_and_login.*\nRECONNECT/),
            re(qr/connect_and_login.*\nRECONNECT/),
            re(qr/Still connected, it's s390, so/),
        ), 'reconnect attempt',
    );
};

subtest 'expect_3270 tests' => sub {
    my $count = 0;
    my $s3270_console_mock = Test::MockModule->new('consoles::s3270');
    $s3270_console_mock->redefine(send_3270 => sub ($self, $command = '', %arg) {
            my $return_lines = {'command_output' => ['OutputArea', 'InputLine', 'RUNNING']};
            $return_lines = {'command_output' => ['success'], 'command_status' => 'ok'} if $command =~ /\b0\b/;
            $return_lines = {'command_output' => ['Wait: Timed out'], 'command_status' => 'any'} if $command =~ /Wait\([1-9],Output\)/;
            if ($command eq 'Snap(Ascii)') {
                ff(5);
                $return_lines = {'command_output' => ["\n", 'InputLine', 'DONE']} if $count == 3;
                $return_lines = {'command_output' => ["OutputArea", 'InputLine', 'DONE']} if $count == 2;
                $return_lines = {'command_output' => ["OutputArea", 'InputLine', 'RUNNING']} if $count == 1;
                $return_lines = {'command_output' => ['OutputArea', 'InputLine', 'MORE...']} if $count == 0;
                $count += 1;
            }
            return $return_lines;
    });

    my $ret = 0;
    stdout_like {
        $ret = $s3270_console->expect_3270();
    } qr/expect_3270.*\n.*/, 'result matches';
    is $ret->[0], 'OutputArea', 'output matches';

    warnings { throws_ok {
            $s3270_console->expect_3270(buffer_full => 'MORE...', buffer_ready => 'DONE', clear_buffer => 1, output_delim => "\n")
    } qr/expect_3270:.*\n.*/, 'expected output matches' };
    warnings { throws_ok {
            $s3270_console->expect_3270(buffer_full => 'MORE...', buffer_ready => 'RUNNING', clear_buffer => 1, output_delim => "\n")
    } qr/expect_3270: timed out.*\n.*/, 'time out' };
};

subtest 'wait_output test' => sub {
    my $s3270_console_mock = Test::MockModule->new('consoles::s3270');
    $s3270_console_mock->redefine(send_3270 => {'command_output' => ['None'], 'command_status' => 'any'});
    warnings { throws_ok { $s3270_console->wait_output() } qr/has the s3270 wait timeout.*\n.*/, 'wait timeout failure expected' };
};

subtest 'sequence_3270 test' => sub {
    $s3270_console->{out} = "success\nconnet($bmwqemu::vars{ZVM_HOST})\nstart to execute process\nok";
    $s3270_console->sequence_3270(qw(String("root")));
    is $s3270_console->{out}, '', 'stdout empty';
};

subtest 'cp_disconnect test' => sub {
    my $s3270_console_mock = Test::MockModule->new('consoles::s3270');
    $s3270_console_mock->redefine(send_3270 => {'command_output' => ['success'], 'command_status' => 'ok'});
    isa_ok $s3270_console->cp_disconnect(), 'HASH';
};

subtest 's3270 disable test' => sub {
    my $s3270_console_mock = Test::MockModule->new('consoles::s3270');
    $s3270_console_mock->redefine(send_3270 => {'command_output' => ['success'], 'command_status' => 'ok'});
    isa_ok $s3270_console->disable(), 'HASH', 'disable can be called';
};

subtest 's3270 finish test' => sub {
    is $s3270_console->finish(), '', 'finish can be called';
};

subtest 's3270 destroy test' => sub {
    is $s3270_console->DESTROY(), '', 'destroy can be called';
};

done_testing();
