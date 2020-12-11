#!/usr/bin/perl
# Copyright © 2020 SUSE LLC

use Test::Most;

use Test::MockModule;
use Test::Output;
use POSIX 'mkfifo';

use consoles::virtio_terminal;
use testapi;
use bmwqemu;


sub prepare_pipes
{
    my ($socket_path) = @_;
    my $pipe_in       = $socket_path . ".in";
    my $pipe_out      = $socket_path . ".out";

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

        sysread($fd_r, my $buf, 1024) while ($running);
        exit 0;
    };

    return {pid => $pid, files => [$pipe_in, $pipe_out]};
}

sub cleanup_pipes
{
    my $obj = shift;
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

done_testing;

