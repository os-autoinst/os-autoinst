#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Mock::Time;
use Test::MockModule;
use Test::MockObject;
use Test::Output qw(combined_like stderr_like);
use Test::Warnings qw(:all :report_warnings);
use POSIX qw(waitpid _exit);
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '5';
use consoles::console;
use backend::ipmi;
use consoles::VNC;
use consoles::sshXtermIPMI;
use cv;

cv::init;
require tinycv;

$bmwqemu::topdir = "$Bin/..";
$bmwqemu::vars{IPMI_HOSTNAME} = 'localhost';
$bmwqemu::vars{IPMI_USER} = 'root';
$bmwqemu::vars{IPMI_PASSWORD} = 'root';

$bmwqemu::vars{WORKER_HOSTNAME} = 'localhost';
$bmwqemu::vars{"HARDWARE_CONSOLE_LOG"} = 1;
$bmwqemu::vars{IPMI_SOL_MAX_RECONNECTS} = 5;

my @printed;
my $testapi_console = 'sshXtermIPMI';
my $testapi_console_mock = Test::MockModule->new("consoles::$testapi_console");
ok my $backend = backend::ipmi->new(), 'backend can be created';
my $backend_mock = Test::MockModule->new('backend::ipmi');
my $localXvnc_mock = Test::MockModule->new('consoles::localXvnc');
my $vnc_mock = Test::MockModule->new('consoles::VNC');
my $inet_mock = Test::MockModule->new('IO::Socket::INET');
my $s = Test::MockObject->new->set_true(qw(sockopt fileno print connected close blocking));

sub _setup_rfb_magic () { $s->set_series('mocked_read', 'RFB 003.006', pack('N', 1)) }
_setup_rfb_magic;

$s->mock(read => sub { $_[1] = $s->mocked_read; length $_[1] });
$s->mock($_ => sub { push @printed, $_[1] }) for qw(print write);
$vnc_mock->redefine(_read_socket => sub { substr(${$_[1]}, $_[3], $_[2]) = $s->mocked_read; length ${$_[1]} });
$inet_mock->redefine(new => $s);
$backend_mock->redefine(do_mc_reset => sub { bmwqemu::diag('IPMI mc reset success'); });
$testapi_console_mock->redefine(backend => $backend);
$localXvnc_mock->redefine(activate => sub ($self) { $self->{DISPLAY} = "display"; });
$vnc_mock->noop('_server_initialization');
$vnc_mock->noop('login');

ok my $sol_connection = consoles::sshXtermIPMI->new($testapi_console, undef), 'sol connection can be established';

subtest 'sshXtermIPMI activate' => sub {
    my $ipc_run_mock = Test::MockModule->new('IPC::Run');
    $ipc_run_mock->redefine(run => sub ($cmd, $stdin, $stdout, $stderr) {
            $$stdin = 'in', $$stdout = 'out', $$stderr = 'err'; return 1;
    });
    stderr_like {
        $sol_connection->activate();
    } qr/Xterm PID:/, 'VNC connection established';

    $ipc_run_mock->redefine(run => sub ($cmd, $stdin, $stdout, $stderr) {
            $$stdin = 'in', $$stdout = 'out', $$stderr = 'Unable to deactivate SOL payload'; return 0;
    });
    throws_ok {
        $sol_connection->activate();
    } qr/Unexpected IPMI response/, 'sshXterm dies with unexpected ipmi response';
};

subtest 'sshXtermIPMI current_screen' => sub {
    my $sol_mock = Test::MockModule->new('consoles::sshXtermIPMI');
    $sol_mock->redefine(waitpid => -1);
    $backend_mock->redefine(ipmi_cmdline => sub { (qw(echo simulating ipmi)) });
    combined_like {
        throws_ok { $sol_connection->current_screen() } qr/Too many IPMI SOL errors/, 'dies on reconnect failure';
    } qr/
        !!!\ consoles::sshXtermIPMI::current_screen:\ IPMI\ SOL\ connection\ died.*
        Xterm\ PID:\ \d+
    /xs, 'sol current_screen failure logs as expected';
};

subtest 'sshXtermIPMI cold reset' => sub {
    $bmwqemu::vars{IPMI_MC_RESET_MAX_TRIES} = $bmwqemu::vars{IPMI_MC_RESET_TIMEOUT} = 3;
    $sol_connection->{activated} = 1;
    stderr_like {
        $sol_connection->do_mc_reset();
    } qr/IPMI mc reset success/, 'cold reset success';
    cmp_ok $sol_connection->{activated}, '==', 0, 'console deactivated after cold reset';
};

subtest 'sshXtermIPMI disable' => sub {
    $sol_connection->{activated} = 1;
    stderr_like {
        $sol_connection->disable();
    } qr/IPMI: simulating/, 'ipmi disable success';
    cmp_ok $sol_connection->{activated}, '==', 0, 'console deactivated after calling disable';
};

done_testing();

