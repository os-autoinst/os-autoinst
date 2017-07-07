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

subtest 'Components autoload' => sub {
    use bmwqemu;
    use backend::baseclass;
    local $ENV{FOO_BAR_BAZ} = 1;
    $bmwqemu::vars{CONNECTIONS_HIJACK} = 1;

    my $backend = backend::baseclass->new(backend => "qemu");
    my @errors = $backend->_autoload_components;

    is scalar(keys %{$backend->{active_components}}), 3;
    ok exists $backend->{active_components}->{'backend::component::dnsserver'};
    ok exists $backend->{active_components}->{'backend::component::proxy'};
    ok exists $backend->{active_components}->{'backend::component::foo'};
    ok !exists $backend->{active_components}->{'backend::component::foobar'};
    ok !exists $backend->{active_components}->{'backend::component::bar'};

    is $backend->{active_components}->{'backend::component::foo'}->prepared, 1, "call to prepare() function works as expected";
    $backend->_stop_components;

    $bmwqemu::vars{CONNECTIONS_HIJACK} = 0;
    local $ENV{FOO_BAR_BAZ} = 0;

    $backend = backend::baseclass->new(backend => "qemu");
    $backend->_autoload_components;

    is scalar(keys %{$backend->{active_components}}), 0;
    ok !exists $backend->{active_components}->{'backend::component::dnsserver'};
    ok !exists $backend->{active_components}->{'backend::component::proxy'};
    ok !exists $backend->{active_components}->{'backend::component::foo'};

    $backend->_stop_components;

    local $ENV{FOO_BAR_BAR} = 1;

    $backend = backend::baseclass->new(backend => "qemu");
    $backend->_autoload_components;

    is scalar(keys %{$backend->{active_components}}), 1;
    ok !exists $backend->{active_components}->{'backend::component::dnsserver'};
    ok !exists $backend->{active_components}->{'backend::component::proxy'};
    ok exists $backend->{active_components}->{'backend::component::bar'};
    ok !exists $backend->{active_components}->{'backend::component::foo'};
    ok !exists $backend->{active_components}->{'backend::component::foobar'};
    isa_ok $backend->{active_components}->{'backend::component::bar'}->backend, "backend::baseclass";
    $backend->_stop_components;

    is scalar(@errors), 1;
    like $errors[0], qr/Bareword "test" not allowed while "strict subs" in/;
};

subtest 'Components explict loading' => sub {
    use bmwqemu;
    use backend::baseclass;

    $bmwqemu::vars{CONNECTIONS_HIJACK} = 0;

    my $backend = backend::baseclass->new(
        backend    => "qemu",
        components => {dnsserver => {optional_arg => 'foo', kill_sleeptime => 2, sleeptime_during_kill => 1, load => 'foo'}});
    my @errors = $backend->_autoload_components;

    is scalar(keys %{$backend->{active_components}}), 1;
    ok exists $backend->{active_components}->{'backend::component::dnsserver'}, "dnsserver component was loaded";
    isa_ok $backend->{active_components}->{'backend::component::dnsserver'}->backend, "backend::baseclass";

    ok !exists $backend->{active_components}->{'backend::component::proxy'}, "proxy component was ignored";
    is $backend->{active_components}->{'backend::component::dnsserver'}->load(), "foo", "Optional argument to backend was successfully passed to component";

    $backend->_stop_components;

    $backend = backend::baseclass->new(backend => "qemu", components => [qw(dnsserver foobar)]);
    $backend->_autoload_components;

    is scalar(keys %{$backend->{active_components}}), 2;
    ok exists $backend->{active_components}->{'backend::component::dnsserver'};
    ok exists $backend->{active_components}->{'backend::component::foobar'}, "component which requires explict loading was started";
    ok !exists $backend->{active_components}->{'backend::component::proxy'};

    $backend->_stop_components;

    $backend = backend::baseclass->new(backend => "foo", components => [qw(proxy)]);
    $backend->_autoload_components;

    is scalar(keys %{$backend->{active_components}}), 1;
    ok !exists $backend->{active_components}->{'backend::component::dnsserver'};
    ok exists $backend->{active_components}->{'backend::component::proxy'};

    $backend->_stop_components;

    is scalar(@errors), 1;
    like $errors[0], qr/Attempt to reload/;
};

subtest 'Test components process' => sub {
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
            });

        $p->start();
        sleep 5;    # give time to print few 'FOOBARFTW' for us
        $p->stop();

        close(CHILD);
        @output = <PARENT>;
        chomp @output;
    }
    is $output[0], "FOOBARFTW";
};


subtest 'Test components restart' => sub {
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
    is $output[0], "FOOBARFTW";
    is $p->is_running, 0, "Process now is stopped";


    # Redefine new code and restart it.
    pipe(PARENT, CHILD);
    $p->code(
        sub {
            close(PARENT);
            open STDERR, ">&", \*CHILD or die $!;
            print STDERR "FOOBAZFTW\n";
        });
    $p->restart();
    is $p->is_running, 1, "Process now is running";
    $p->stop();
    close(CHILD);
    @output = <PARENT>;
    chomp @output;
    is $output[0], "FOOBAZFTW";
    is $p->is_running, 0, "Process now is not running";
    @output = ('');

    pipe(PARENT, CHILD);
    $p->restart();
    is $p->is_running, 1, "Process now is running";
    $p->stop();
    close(CHILD);
    @output = <PARENT>;
    chomp @output;
    is $output[0], "FOOBAZFTW";

};

subtest 'Test components baseclass' => sub {
    use backend::component;

    my $c = backend::component->new();

    can_ok($c, qw(verbose load backend _diag));

    my $buffer;
    {
        open my $handle, '>', \$buffer;
        local *STDERR = $handle;
        $c->_diag("FOOTEST");
    };
    like $buffer, qr/>> main::__ANON__\(\): FOOTEST/;
};

done_testing;
