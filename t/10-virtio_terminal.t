#!/usr/bin/perl
# Copyright © 2020-2021 SUSE LLC

use Test::Most;
use Mojo::Base -strict, -signatures;
use Test::Warnings qw(:all :report_warnings);

# OpenQA::Test::TimeLimit not used as `prepare_pipes` defines an ALRM handler
# internally already
use Test::MockModule;
use Test::Output;
use POSIX 'mkfifo';

use consoles::virtio_terminal;
use testapi;
use bmwqemu;


sub prepare_pipes ($socket_path, $write_buffer) {
    my $pipe_in  = $socket_path . ".in";
    my $pipe_out = $socket_path . ".out";

    for (($pipe_in, $pipe_out)) {
        unlink $_ if (-e $_);
        mkfifo($_, 0666) or die("Cannot create fifo pipe $_");
    }

    my $pid = fork || do {
        my $running = 1;
        $SIG{USR1} = sub { $running = 0; };
        $SIG{ALRM} = sub {
            die('Timeout for pipe other side helper');
        };
        alarm 60;

        open(my $fd_r, "<", $pipe_in)
          or die "Can't open in pipe for writing $!";
        open(my $fd_w, ">", $pipe_out)
          or die "Can't open out pipe for reading $!";

        syswrite($fd_w, $write_buffer) if ($write_buffer);

        sysread($fd_r, my $buf, 1024) while ($running);
        exit 0;
    };

    return {pid => $pid, files => [$pipe_in, $pipe_out]};
}

sub cleanup_pipes ($obj) {
    kill 'USR1', $obj->{pid};
    waitpid(-1, 0);
    unlink for (@{$obj->{files}});
}

subtest "Test open_pipe() error condition" => sub {
    my $socket_path    = './virtio_console_open_test';
    my $file_mock      = Test::MockModule->new('Mojo::File');
    my $vterminal_mock = Test::MockModule->new('consoles::virtio_terminal');
    $vterminal_mock->redefine("get_pipe_sz", sub { return; });

    my $helper = prepare_pipes($socket_path);
    my $term   = consoles::virtio_terminal->new('unit-test-console', {socked_path => $socket_path});
    combined_like { dies_ok { $term->open_pipe(); } 'Expect die if pipe_sz fail' } qr/\[debug\] <<<.*open_pipe/, 'log';
    cleanup_pipes($helper);

    my $size = 1024;
    $file_mock->redefine(slurp => sub { return 65536; });
    $vterminal_mock->redefine("get_pipe_sz", sub { return 1024; });
    $vterminal_mock->redefine("set_pipe_sz", sub {
            my ($self, $fd, $newsize) = @_;
            return if ($newsize > 2048);
            return $size = $newsize;
    });
    $helper = prepare_pipes($socket_path);
    $term   = consoles::virtio_terminal->new('unit-test-console', {socked_path => $socket_path});
    stderr_like { $term->open_pipe() } qr/Set PIPE_SZ from 1024 to 2048/, 'Log mention size';
    cleanup_pipes($helper);
    is($size, 2048, "PIPE_SZ is 2048");

    $size = 1024;
    $vterminal_mock->redefine("set_pipe_sz", undef);
    $helper = prepare_pipes($socket_path);
    $term   = consoles::virtio_terminal->new('unit-test-console', {socked_path => $socket_path});
    stderr_like { $term->open_pipe() } qr/Set PIPE_SZ from 1024 to 1024/, 'Log mention new size';
    cleanup_pipes($helper);
    is($size, 1024, "Size didn't changed");

    $size = 1024;
    $vterminal_mock->redefine("set_pipe_sz", sub {
            my ($self, $fd, $newsize) = @_;
            return $size = $newsize;
    });

    $helper = prepare_pipes($socket_path);
    $term   = consoles::virtio_terminal->new('unit-test-console', {socked_path => $socket_path});
    combined_like { $term->open_pipe() } qr/Set PIPE_SZ from 1024 to 65536/, 'Log mention new size';
    cleanup_pipes($helper);
    is($size, 65536, "PIPE_SZ is 65536");

    testapi::set_var('VIRTIO_CONSOLE_PIPE_SZ', 5555);
    $helper = prepare_pipes($socket_path);
    $term   = consoles::virtio_terminal->new('unit-test-console', {socked_path => $socket_path});
    stderr_like { $term->open_pipe() } qr/Set PIPE_SZ from 1024 to 5555/, 'Log mention new size';
    cleanup_pipes($helper);
    is($size, 5555, "PIPE_SZ is 5555 from VIRTIO_CONSOLE_PIPE_SZ");

    $term = consoles::virtio_terminal->new('unit-test-console', {socked_path => $socket_path});
    combined_like { throws_ok { $term->open_pipe() } qr/No such file or directory/, "Throw exception if pipe doesn't exists" }
    qr/\[debug\] <<<.*open_pipe/, 'log for open_pipe on non-existant pipe';
};

subtest "Test snapshot handling" => sub {
    $bmwqemu::logger = Mojo::Log->new(level => 'error');    # hide debug messages within this test

    my $socket_path = './virtio_console_open_test';
    my $test_data   = "Test data foo";
    my $helper      = prepare_pipes($socket_path, $test_data);
    my $term        = consoles::virtio_terminal->new('unit-test-console', {socked_path => $socket_path});

    is_deeply($term->get_snapshot(),                                  undef, "Return undef if no name is given");
    is_deeply($term->get_snapshot('unknown_snapshot'),                undef, "Return undef, if snapshotname doesn't exist");
    is_deeply($term->get_snapshot('unknown_snapshot', 'unknown_key'), undef, "Return undef, if snapshot and key doesn't exist");
    is_deeply($term->set_snapshot(),                                  undef, "Return undef, if snapshot name not given");
    is_deeply($term->set_snapshot('foo'),                             undef, "Return undef, if key not given");
    is_deeply($term->{snapshots},                                     {},    "Snapshots are empty");

    $term->select();
    is_deeply($term->{snapshots}, {}, "Snapshots are empty after select/activate");

    $term->save_snapshot('snap1');
    is($term->get_snapshot('snap1', 'buffer'),    $test_data, '[snap1] virtio_terminal stored all available data');
    is($term->get_snapshot('snap1', 'activated'), 1,          '[snap1] console snapshot is activated');
    is_deeply($term->get_snapshot('snap1', 'unknown_key'), undef,                                  "[snap1] return undef, if key doesn't exist");
    is_deeply($term->get_snapshot('snap1'),                {activated => 1, buffer => $test_data}, '[snap1] Snapshots data verified');

    $term->screen()->read_until('Test data ', 60);
    $term->save_snapshot('snap2');
    is($term->get_snapshot('snap2', 'buffer'),    'foo', '[snap2] virtio_terminal stored all available data');
    is($term->get_snapshot('snap2', 'activated'), 1,     '[snap2] console snapshot is activated');
    is_deeply($term->get_snapshot('snap2'), {activated => 1, buffer => 'foo'}, '[snap2] Snapshots data verified');

    $term->reset();
    is_deeply($term->screen()->peak(), 'foo', 'Verified peak retrieves "foo"');
    is($term->{activated}, 0, 'Verify console is not activated after reset()');
    $term->save_snapshot('snap3');

    $term->load_snapshot('snap1');
    is_deeply($term->screen()->peak(), $test_data, '[snap1] carry over buffer sucessful loaded');
    is($term->{activated}, 1, '[snap1] console is still activated');

    $term->load_snapshot('snap3');
    is_deeply($term->screen()->peak(), 'foo', '[snap3] carry over buffer sucessful loaded');
    is($term->{activated}, 0, '[snap3] console is not activated');

    $term->disable();
    $term->{preload_buffer} = 'test123';
    $term->save_snapshot('snap4');
    is($term->get_snapshot('snap4', 'buffer'), 'test123', '[snap4] virtio_terminal stored preload_buffer if screen is not set');
    $term->{preload_buffer} = 'this should be overwritten by load_snapshot';
    $term->load_snapshot('snap4');
    is($term->{preload_buffer}, 'test123', '[snap4] preload_buffer is restored after loading snapshot');

    cleanup_pipes($helper);
};

done_testing;

