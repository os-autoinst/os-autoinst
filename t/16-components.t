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
use lib "$FindBin::Bin/lib";

BEGIN {
    unshift @INC, '..';
}

subtest 'backend::component' => sub {
    use backend::component;

    my $c = backend::component->new();

    can_ok($c, qw(verbose load backend _diag));

    my $buffer;
    {
        open my $handle, '>', \$buffer;
        local *STDERR = $handle;
        $c->_diag("FOOTEST");
    };
    like $buffer, qr/>> main::__ANON__\(\): FOOTEST/, "diag() correct output format";
};

subtest 'backend::component::process basic functions' => sub {
    use backend::component::process;

    my $p = backend::component::process->new();
    eval {
        $p->start();
        $p->stop();
    };
    ok $@, "Error expected";
    like $@, qr/Nothing to do/, "Process with no code nor execute command, will fail";

    $p = backend::component::process->new();
    eval { $p->_fork(); };
    ok $@, "Error expected";
    like $@, qr/Can't spawn child without code/, "_fork() with no code will fail";

    my @output;
    {
        pipe(PARENT, CHILD);

        my $p = backend::component::process->new(
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

subtest 'backend::component::process is_running()' => sub {
    use backend::component::process;

    my @output;
    pipe(PARENT, CHILD);

    my $p = backend::component::process->new(
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

subtest 'backend::component::process execute()' => sub {
    use backend::component::process;
    my $p = backend::component::process->new(execute => "$FindBin::Bin/data/process_check.sh")->start();
    is $p->getline,     "TEST normal print\n", 'Get right output from stdout';
    is $p->err_getline, "TEST error print\n",  'Get right output from stderr';
    is $p->is_running,  1,                     'process is still waiting for our input';
    $p->write("FOOBAR");
    is $p->read, "you entered FOOBAR\n", 'process received input and printed it back' for qw(getline );
    $p->stop();
    is $p->is_running, 0, 'process is not running anymore';

    $p = backend::component::process->new(execute => "$FindBin::Bin/data/process_check.sh", args => [qw(FOO BAZ)])->start();
    is $p->stdout,      "TEST normal print\n", 'Get right output from stdout';
    is $p->err_getline, "TEST error print\n",  'Get right output from stderr';
    is $p->is_running,  1,                     'process is still waiting for our input';
    $p->write("FOOBAR");
    is $p->getline, "you entered FOOBAR\n", 'process received input and printed it back';
    $p->stop();
    is $p->is_running,  0,           'process is not running anymore';
    is $p->getline,     "FOO BAZ\n", 'process received extra arguments';
    is $p->exit_status, 100,         'able to retrieve function return';

    $p = backend::component::process->new(separate_err => 0, execute => "$FindBin::Bin/data/process_check.sh");
    $p->start();
    is $p->getline, "TEST error print\n",  'Get STDERR output from stdout, always in getline()';
    is $p->getline, "TEST normal print\n", 'Still able to get stdout output, always in getline()';
    $p->stop();

    my $p2 = backend::component::process->new(separate_err => 0, execute => "$FindBin::Bin/data/process_check.sh", set_pipes => 0);
    $p2->start();
    is $p2->getline, undef, "pipes are correctly disabled";
    is $p2->getline, undef, "pipes are correctly disabled";
    $p2->stop();
    is $p2->exit_status, 0, 'take exit status even with set_pipes = 0 (we killed it)';
};

subtest 'backend::component::process code()' => sub {
    use backend::component::process;
    use IO::Select;
    my $p = backend::component::process->new(
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

    $p = backend::component::process->new(
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

    $p = backend::component::process->new(code => sub { die "Fatal error"; });
    $p->start();
    $p->stop();
    is $p->is_running,    0, 'process is not running';
    is $p->return_status, 0, 'process returned result is 0';
    like((@{$p->error})[0], qr/Fatal error/, 'right error');

    $p = backend::component::process->new(
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

    $p = backend::component::process->new(
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

subtest 'backend::component autoload' => sub {
    use bmwqemu;
    use backend::baseclass;
    local $ENV{FOO_BAR_BAZ} = 1;
    $bmwqemu::vars{CONNECTIONS_HIJACK} = 1;

    my $backend = backend::baseclass->new(backend => "qemu");
    my @errors = $backend->_autoload_components;

    is scalar(keys %{$backend->{active_components}}), 3, "3 active components";
    ok exists $backend->{active_components}->{'backend::component::dnsserver'}, 'dnsserver is active';
    ok exists $backend->{active_components}->{'backend::component::proxy'},     'proxy is active';
    ok exists $backend->{active_components}->{'backend::component::foo'},       'foo is active';
    ok !exists $backend->{active_components}->{'backend::component::foobar'},   'foobar is not active';
    ok !exists $backend->{active_components}->{'backend::component::bar'},      'bar is not active';

    is $backend->{active_components}->{'backend::component::foo'}->prepared, 1, "call to prepare() function works as expected";
    $backend->_stop_components;

    $bmwqemu::vars{CONNECTIONS_HIJACK} = 0;
    local $ENV{FOO_BAR_BAZ} = 0;

    $backend = backend::baseclass->new(backend => "qemu");
    $backend->_autoload_components;

    is scalar(keys %{$backend->{active_components}}), 0, "no active components";
    ok !exists $backend->{active_components}->{'backend::component::dnsserver'}, 'dnsserver is not active';
    ok !exists $backend->{active_components}->{'backend::component::proxy'},     'proxy is not active';
    ok !exists $backend->{active_components}->{'backend::component::foo'},       'foo is not active';

    $backend->_stop_components;

    local $ENV{FOO_BAR_BAR} = 1;

    $backend = backend::baseclass->new(backend => "qemu");
    $backend->_autoload_components;

    is scalar(keys %{$backend->{active_components}}), 1, 'there is 1 active component';
    ok !exists $backend->{active_components}->{'backend::component::dnsserver'}, 'dnsserver is not active';
    ok !exists $backend->{active_components}->{'backend::component::proxy'},     'proxy is not active';
    ok exists $backend->{active_components}->{'backend::component::bar'},        'bar is active';
    ok !exists $backend->{active_components}->{'backend::component::foo'},       'foo is not active';
    ok !exists $backend->{active_components}->{'backend::component::foobar'},    'foobar is not active';
    isa_ok $backend->{active_components}->{'backend::component::bar'}->backend, "backend::baseclass";
    $backend->_stop_components;

    is scalar(@errors), 1, 'there was one expected error';
    like $errors[0], qr/Bareword "test" not allowed while "strict subs" in/, 'right error detected';
};

subtest 'backend::component selective load' => sub {
    use bmwqemu;
    use backend::baseclass;

    $bmwqemu::vars{CONNECTIONS_HIJACK} = 0;

    my $backend = backend::baseclass->new(
        backend    => "qemu",
        components => {dnsserver => {optional_arg => 'foo', kill_sleeptime => 2, sleeptime_during_kill => 1, load => 'foo'}});
    my @errors = $backend->_autoload_components;

    is scalar(keys %{$backend->{active_components}}), 1, 'one active component is present';
    ok exists $backend->{active_components}->{'backend::component::dnsserver'}, "dnsserver component was loaded";
    isa_ok $backend->{active_components}->{'backend::component::dnsserver'}->backend, "backend::baseclass";

    ok !exists $backend->{active_components}->{'backend::component::proxy'}, "proxy component was ignored";
    is $backend->{active_components}->{'backend::component::dnsserver'}->load(), "foo", "Optional argument to backend was successfully passed to component";

    $backend->_stop_components;

    $backend = backend::baseclass->new(backend => "qemu", components => [qw(dnsserver foobar)]);
    $backend->_autoload_components;

    is scalar(keys %{$backend->{active_components}}), 2, 'two active components are present';
    ok exists $backend->{active_components}->{'backend::component::dnsserver'}, "dnsserver component was loaded";
    ok exists $backend->{active_components}->{'backend::component::foobar'},    "component which requires explict loading was started";
    ok !exists $backend->{active_components}->{'backend::component::proxy'},    "proxy component was not loaded";

    $backend->_stop_components;

    $backend = backend::baseclass->new(backend => "foo", components => [qw(proxy)]);
    $backend->_autoload_components;

    is scalar(keys %{$backend->{active_components}}), 1, 'one active component is present';
    ok !exists $backend->{active_components}->{'backend::component::dnsserver'}, "dnsserver component was not loaded";
    ok exists $backend->{active_components}->{'backend::component::proxy'},      "proxy component was loaded";

    $backend->_stop_components;

    is scalar(@errors), 1, 'there was one expected error';
    like $errors[0], qr/Attempt to reload/, 'right error detected';
};

done_testing;
