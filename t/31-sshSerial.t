#!/usr/bin/perl

use Test::Most;
use Mojo::Base -strict, -signatures;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib";
use OpenQA::Test::TimeLimit '20';
use Test::MockObject;
use Test::MockModule;
use Test::Warnings ':report_warnings';
use Test::Output;
use Net::SSH2 'LIBSSH2_ERROR_EAGAIN';

use consoles::sshSerial;

my $eagain = [
    LIBSSH2_ERROR_EAGAIN,
    'LIBSSH2_ERROR_EAGAIN',
    'Operation would block'
];

my $mock_backend = Test::MockObject->new();
my $mock_ssh     = Test::MockObject->new();
my $mock_channel = Test::MockObject->new();
my $mock_bmwqemu = Test::MockModule->new('bmwqemu');

$mock_ssh->{error} = undef;

$mock_channel->{write_limits} = [];
$mock_channel->{write_buffer} = '';
$mock_channel->{read_queue}   = [];
$mock_channel->{blocking}     = 1;

$mock_channel->mock(pty      => sub { 1 });
$mock_channel->mock(ext_data => sub { 1 });
$mock_channel->mock(shell    => sub { 1 });
$mock_channel->mock(send_eof => sub { 1 });

$mock_ssh->mock(channel => sub { $mock_channel });

$mock_backend->mock(new_ssh_connection => sub { $mock_ssh });

$mock_bmwqemu->noop('diag', 'fctinfo', 'log_call');

$mock_channel->mock(blocking => sub ($self, $arg) {
        $self->{blocking} = $arg if defined($arg);
        return $self->{blocking};
});

$mock_channel->mock(read => sub ($self, $, $size) {
        my $data = shift @{$self->{read_queue}};

        if (!defined($data)) {
            $mock_ssh->{error} = $eagain unless defined($mock_ssh->{error});
            return undef;
        }

        if (length($data) > $size) {
            unshift @{$self->{read_queue}}, substr($data, $size);
            $data = substr($data, 0, $size);
        }

        $_[1] = $data;
        return length($data);
});

$mock_channel->mock(write => sub ($self, $data) {
        my $limit = shift @{$self->{write_limits}};

        if (defined($limit) && $limit < 0) {
            $mock_ssh->{error} = $eagain unless defined($mock_ssh->{error});
            return undef;
        }

        $data = substr($data, 0, $limit) if defined($limit);
        $self->{write_buffer} .= $data;
        return length($data);
});

$mock_ssh->mock(blocking => sub { return $mock_channel->blocking($_[1]) });

$mock_ssh->mock(error => sub ($self) {
        return undef unless defined($self->{error});
        return ${$self->{error}}[0] if ((caller(0))[5]);
        return @{$self->{error}};
});

$mock_ssh->mock(die_with_error => sub { die $_[1] });

subtest 'Read test' => sub {
    $mock_ssh->{error}            = undef;
    $mock_channel->{write_limits} = [];
    $mock_channel->{write_buffer} = '';
    $mock_channel->{read_queue}   = [
        'First line',
        'Second line',
        undef,
        'Third line'
    ];
    $mock_channel->{blocking} = 1;

    my $console = consoles::sshSerial->new(undef, {hostname => 'localhost'});
    $console->backend($mock_backend);
    $console->activate();
    my $screen = $console->screen();
    my $data;
    my $ret;

    ok !$mock_channel->{blocking}, 'sshSerial sets non-blocking mode';

    $ret = $screen->do_read($data);
    is $data, 'First line', 'first line can be read';
    is $ret, length($data), 'first line has correct length';

    $ret = $screen->do_read($data);
    is $data, 'Second line', 'second line can be read';
    is $ret, length($data), 'second line has correct length';

    # Test that do_read() loops on EAGAIN until data is available
    $ret = $screen->do_read($data, timeout => 1);
    is $data, 'Third line', 'data can be read with timeout';
    is $ret, length($data), 'read with timeout has correct length';

    # Test do_read() timeout with mocked "elapsed" to skip sleeping
    my $serial_screen_mock = Test::MockModule->new('consoles::serial_screen');
    $serial_screen_mock->redefine(elapsed => 1);
    $ret = $screen->do_read($data, timeout => 1);
    is $ret, undef, 'read aborts after timeout on no data';
    $serial_screen_mock->unmock('elapsed');

    # Test that read_until() can correctly assemble fragmented messages
    $mock_channel->{read_queue} = [
        'This message ',
        undef,
        'is fragmented',
        ' a little b',
        undef,
        'it more t',
        'han usual.',
    ];

    $ret = $screen->read_until('frag', 1);
    ok $$ret{matched}, 'data can be read partially';
    is $$ret{string}, 'This message is frag', 'fragment read as expected';

    $ret = $screen->read_until('bit', 1);
    ok $$ret{matched}, 'second part of data can be read partially';
    is $$ret{string}, 'mented a little bit', 'second part of data correctly read';

    # mocked times for faster returns in tests
    my @times = (0, 1, 1);
    $serial_screen_mock->redefine(elapsed => sub { shift @times });
    $ret = $screen->read_until('foo', 1);
    $serial_screen_mock->unmock('elapsed');
    ok !$$ret{matched}, 'read until reports failure if search term not found';
    is $$ret{string}, ' more than usual.', 'rest of data has been read';
    is_deeply $mock_channel->{read_queue}, [], 'nothing left in read queue';
};

subtest 'Write test' => sub {
    $mock_ssh->{error}            = undef;
    $mock_channel->{write_limits} = [];
    $mock_channel->{write_buffer} = '';
    $mock_channel->{read_queue}   = [];
    $mock_channel->{blocking}     = 1;

    my $console = consoles::sshSerial->new(undef, {hostname => 'localhost'});
    $console->backend($mock_backend);
    $console->activate();
    my $screen = $console->screen();

    ok !$mock_channel->{blocking}, 'sshSerial sets non-blocking mode';

    $screen->type_string({text => 'Hello, world!'});
    is $mock_channel->{write_buffer}, 'Hello, world!', 'expected data written';

    # Test that type_string() will loop until all data is written
    $mock_channel->{write_buffer} = '';
    $mock_channel->{write_limits} = [5, 2, -1, 10, -1, -1, -1, 8];
    $screen->type_string({text => 'A slightly longer test string.'});
    is $mock_channel->{write_buffer}, 'A slightly longer test string.', 'larger write buffer written in loop';
};

done_testing;
