#!/usr/bin/perl

# Copyright (C) 2017 SUSE LLC
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

use 5.018;
use warnings;
use strict;
use Test::More;
use POSIX;
use FindBin;
use Mojo::File qw(tempfile path);
use lib "$FindBin::Bin/lib";

BEGIN {
    unshift @INC, '..';
}

subtest process => sub {
    use process;

    my $c = process->new();

    can_ok($c, qw(verbose _diag));

    my $buffer;
    {
        open my $handle, '>', \$buffer;
        local *STDERR = $handle;
        $c->_diag("FOOTEST");
    };
    like $buffer, qr/>> main::__ANON__\(\): FOOTEST/, "diag() correct output format";
};

subtest 'process basic functions' => sub {
    use process;

    my $p = process->new();
    eval {
        $p->start();
        $p->stop();
    };
    ok $@, "Error expected";
    like $@, qr/Nothing to do/, "Process with no code nor execute command, will fail";

    $p = process->new();
    eval { $p->_fork(); };
    ok $@, "Error expected";
    like $@, qr/Can't spawn child without code/, "_fork() with no code will fail";

    my @output;
    {
        pipe(PARENT, CHILD);

        my $p = process->new(
            code => sub {
                close(PARENT);
                open STDERR, ">&", \*CHILD or die $!;
                print STDERR "FOOBARFTW\n" while 1;
            })->start();
        sleep 1;    # Give chance to print some output
        $p->stop();

        close(CHILD);
        @output = <PARENT>;
        chomp @output;
    }
    is $output[0], "FOOBARFTW", 'right output';
};

subtest 'process is_running()' => sub {
    use process;

    my @output;
    pipe(PARENT, CHILD);

    my $p = process->new(
        code => sub {
            close(PARENT);
            open STDERR, ">&", \*CHILD or die $!;
            print STDERR "FOOBARFTW\n";
        });

    $p->start();
    $p->stop();

    close(CHILD);
    @output = <PARENT>;
    close(PARENT);
    chomp @output;
    is $output[0], "FOOBARFTW", 'right output from process';
    is $p->is_running, 0, "Process now is stopped";


    # Redefine new code and restart it.
    pipe(PARENT, CHILD);
    $p->code(
        sub {
            close(PARENT);
            open STDERR, ">&", \*CHILD or die $!;
            print STDERR "FOOBAZFTW\n";
        });
    $p->restart()->restart()->restart();
    is $p->is_running, 1, "Process now is running";
    $p->stop();
    close(CHILD);
    @output = <PARENT>;
    chomp @output;
    is $output[0], "FOOBAZFTW", 'right output from process';
    is $p->is_running, 0, "Process now is not running";
    @output = ('');

    pipe(PARENT, CHILD);
    $p->restart();
    is $p->is_running, 1, "Process now is running";
    $p->stop();
    close(CHILD);
    @output = <PARENT>;
    chomp @output;
    is $output[0], "FOOBAZFTW", 'right output from process';

};

subtest 'process execute()' => sub {
    use process;
    my $p = process->new(execute => "$FindBin::Bin/data/process_check.sh")->start();
    is $p->getline,     "TEST normal print\n", 'Get right output from stdout';
    is $p->err_getline, "TEST error print\n",  'Get right output from stderr';
    is $p->is_running,  1,                     'process is still waiting for our input';
    $p->write("FOOBAR");
    is $p->read, "you entered FOOBAR\n", 'process received input and printed it back';
    $p->stop();
    is $p->is_running, 0, 'process is not running anymore';

    $p = process->new(execute => "$FindBin::Bin/data/process_check.sh", args => [qw(FOO BAZ)])->start();
    is $p->stdout,      "TEST normal print\n", 'Get right output from stdout';
    is $p->err_getline, "TEST error print\n",  'Get right output from stderr';
    is $p->is_running,  1,                     'process is still waiting for our input';
    $p->write("FOOBAR");
    is $p->getline, "you entered FOOBAR\n", 'process received input and printed it back';
    $p->stop();
    is $p->is_running,  0,           'process is not running anymore';
    is $p->getline,     "FOO BAZ\n", 'process received extra arguments';
    is $p->exit_status, 100,         'able to retrieve function return';

    $p = process->new(separate_err => 0, execute => "$FindBin::Bin/data/process_check.sh");
    $p->start();
    is $p->is_running, 1, 'process is still running';
    is $p->getline, "TEST error print\n", 'Get STDERR output from stdout, always in getline()';
    $p->stop();
    is $p->getline, "TEST normal print\n", 'Still able to get stdout output, always in getline()';

    my $p2 = process->new(separate_err => 0, execute => "$FindBin::Bin/data/process_check.sh", set_pipes => 0);
    $p2->start();
    is $p2->getline, undef, "pipes are correctly disabled";
    is $p2->getline, undef, "pipes are correctly disabled";
    $p2->stop();
    is $p2->exit_status, 0, 'take exit status even with set_pipes = 0 (we killed it)';

    my $buffer;
    {
        open my $handle, '>', \$buffer;
        local *STDERR = $handle;
        $p = process->new(verbose => 1, separate_err => 0, execute => "$FindBin::Bin/data/process_check.sh", max_kill_attempts => -1);    # ;)
        $p->start();
        my $pid = $p->pid();
        $p->stop();
        is $p->is_running, 1, 'process is still running';
        $p->max_kill_attempts(50);
        $p->stop();
        is $p->is_running, 0, 'process is shutten down';
        like $buffer, qr/process::stop\(\): Could not kill process id: $pid/, 'Process could not be killed';
        like((@{$p->error})[0], qr/Could not kill process/, 'Error is not empty if process could not be killed');
    }

    $p = process->new(
        verbose           => 1,
        separate_err      => 0,
        blocking_stop     => 1,
        execute           => "$FindBin::Bin/data/process_check.sh",
        max_kill_attempts => -1                                       # ;)
    )->start()->stop();

    is $p->is_running, 0, 'process is shutten down by kill signal when "blocking_stop => 1"';

    my $pidfile = tempfile;
    $p = process->new(
        verbose           => 1,
        separate_err      => 0,
        blocking_stop     => 1,
        execute           => "$FindBin::Bin/data/process_check.sh",
        max_kill_attempts => -1,                                      # ;)
        pidfile           => $pidfile
    )->start();
    my $pid = path($pidfile)->slurp();
    is -e $pidfile, 1, 'Pidfile is there!';
    is $pid, $p->pid, "Pidfile was correctly written";
    $p->stop();
    is -e $pidfile, undef, 'Pidfile got removed after stop()';

    $pidfile = tempfile;
    $p       = process->new(
        verbose           => 1,
        separate_err      => 0,
        blocking_stop     => 1,
        execute           => "$FindBin::Bin/data/process_check.sh",
        max_kill_attempts => -1,                                      # ;)
    )->start();
    $p->write_pidfile($pidfile);
    my $pid = path($pidfile)->slurp();
    is -e $pidfile, 1, 'Pidfile is there!';
    is $pid, $p->pid, "Pidfile was correctly written";
    $p->stop();
    is -e $pidfile, undef, 'Pidfile got removed after stop()';

    $p = process->new(
        verbose           => 1,
        separate_err      => 0,
        blocking_stop     => 1,
        execute           => "$FindBin::Bin/data/process_check.sh",
        max_kill_attempts => -1,                                      # ;)
    )->start();
    is $p->write_pidfile(), undef, "No filename given to write_pidfile";
    $p->stop()

};

subtest 'process code()' => sub {
    use process;
    use IO::Select;
    my $p = process->new(
        code => sub {
            my ($self)        = shift;
            my $parent_output = $self->channel_out;
            my $parent_input  = $self->channel_in;

            print $parent_output "FOOBARftw\n";
            print "TEST normal print\n";
            print STDERR "TEST error print\n";
            print "Enter something : ";
            my $a = <STDIN>;
            chomp($a);
            print "you entered $a\n";
            my $parent_stdin = $parent_input->getline;
            print $parent_output "PONG\n" if $parent_stdin eq "PING\n";
            exit 0;
        })->start();
    $p->channel_in->write("PING\n");
    is $p->getline,    "TEST normal print\n", 'Get right output from stdout';
    is $p->stderr,     "TEST error print\n",  'Get right output from stderr';
    is $p->is_running, 1,                     'process is running';
    $p->write("FOOBAR\n");
    is(IO::Select->new($p->read_stream)->can_read(10), 1, 'can read from stdout handle');
    is $p->getline, "Enter something : you entered FOOBAR\n", 'can read output';
    $p->stop();

    is $p->channel_out->getline,         "FOOBARftw\n", "can read from internal channel";
    is $p->channel_read_handle->getline, "PONG\n",      "can read from internal channel";
    is $p->is_running, 0, 'process is not running';
    $p->restart();

    $p->channel_write("PING");
    is $p->getline,    "TEST normal print\n", 'Get right output from stdout';
    is $p->stderr,     "TEST error print\n",  'Get right output from stderr';
    is $p->is_running, 1,                     'process is running';
    is $p->channel_read(), "FOOBARftw\n", "Read from channel while process is running";
    $p->write("FOOBAR");
    is(IO::Select->new($p->read_stream)->can_read(10), 1, 'can read from stdout handle');

    is $p->read_all, "Enter something : you entered FOOBAR\n", 'Get right output from stdout';
    $p->stop();

    my @result = $p->read_all;
    is @result, 0, 'output buffer is now empty';

    is $p->channel_read_handle->getline, "PONG\n", "can read from internal channel";
    is $p->is_running, 0, 'process is not running';

    $p = process->new(
        separate_err => 0,
        code         => sub {
            my ($self)        = shift;
            my $parent_output = $self->channel_out;
            my $parent_input  = $self->channel_in;

            print "TEST normal print\n";
            print STDERR "TEST error print\n";
            sleep 1;
            return "256";
        })->start();
    is $p->getline, "TEST normal print\n", 'Get right output from stderr/stdout';
    is $p->getline, "TEST error print\n",  'Get right output from stderr/stdout';
    $p->stop();
    is $p->is_running,  0,   'process is not running';
    is $p->exit_status, 256, 'right return code';

    $p = process->new(sub { die "Fatal error"; });
    $p->start();
    $p->stop();
    is $p->is_running,    0, 'process is not running';
    is $p->return_status, 0, 'process returned result is 0';
    like((@{$p->error})[0], qr/Fatal error/, 'right error');

    $p = process->new(
        separate_err => 0,
        set_pipes    => 0,
        code         => sub {
            print "TEST normal print\n";
            print STDERR "TEST error print\n";
            return "256";
        })->start();
    is $p->getline, undef, 'no output from pipes expected';
    is $p->getline, undef, 'no output from pipes expected';
    sleep 1;
    $p->stop();
    is $p->exit_status, 256, "grab exit_status even if no pipes are set";

    $p = process->new(
        separate_err => 0,
        code         => sub {
            print STDERR "TEST error print\n" for (1 .. 6);
            my $a = <STDIN>;
        })->start();
    sleep 1;
    like $p->stderr_all, qr/TEST error print/, 'read all from stderr, is like reading all from stdout when separate_err = 0';
    $p->stop()->separate_err(1)->start();
    sleep 1;
    $p->stop();
    like $p->stderr_all, qr/TEST error print/, 'read all from stderr works';
    is $p->read_all, '', 'stdout is empty';
};

subtest process_debug => sub {
    my $buffer;
    local $ENV{OSAUTOINST_PROCESS_DEBUG} = 1;

    {
        # We have to unload and load it back from memory to enable debug. (the ENV value is considered only in compile-time)
        open my $handle, '>', \$buffer;
        local *STDERR = $handle;
        delete $INC{'process.pm'};
        eval "no warnings; require process";    ## no critic
        process->new(sub { 1; })->start()->stop();
    }

    like $buffer, qr/Fork: \{/, 'setting OSAUTOINST_PROCESS_DEBUG to 1 enables debug mode when forking process';

    undef $buffer;
    {
        open my $handle, '>', \$buffer;
        local *STDERR = $handle;
        delete $INC{'process.pm'};
        eval "no warnings; require process";    ## no critic
        process->new(execute => "$FindBin::Bin/data/process_check.sh")->start()->stop();
    }

    like $buffer, qr/Execute: .*process_check.sh/, 'setting OSAUTOINST_PROCESS_DEBUG to 1 enables debug mode when executing external process';
};

done_testing;
