# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2016 SUSE LLC
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

package autotest;
use strict;
use bmwqemu;
use Exporter 'import';
our @EXPORT_OK = qw(loadtest $current_test $selected_console $last_milestone_console query_isotovideo);

use File::Basename;
use File::Spec;
use Socket;
use IO::Handle;
use POSIX '_exit';
use cv;
use Scalar::Util 'blessed';
use Mojo::IOLoop::ReadWriteProcess 'process';
use Mojo::IOLoop::ReadWriteProcess::Session 'session';

our %tests;        # scheduled or run tests
our @testorder;    # for keeping them in order
our $isotovideo;
our $process;
=head1 Introduction

OS Autoinst decides which test modules to run based on a distribution specific
script called main.pm. This is either located in $vars{PRODUCTDIR} or
$vars{CASEDIR} (e.g. <distribution>/products/<product>/main.pm).

This script does not actually run the tests, but queues them to be run by
autotest.pm. A test is queued by calling the loadtest function which is also
located in autotest.pm. The test modules are executed in the same order that
loadtest is called.

=cut

=head2 loadtest

	loadtest(<string>, [ name => <string>, run_args => <OpenQA::Test::RunArgs> ]);

Queue a test module for execution by the test runner. The first argument is
mandatory and specifies the Perl module name containing the test code to be run.

The next two arguments are optional and rarely used. First there is name which
can be used to give the test a different display name from the Perl source
file.

Then there is the run_args object, which must be a subclass of
OpenQA::Test::RunArgs. This is passed to the run() method of the test module
when it is executed. This is useful if you need to load the same test module
multiple times within a single test, but with different parameters each time.

Usually get_var and set_var are used to pass parameters to a test. However if
you use set_var multiple times inside main.pm then the final value you set
will be the one seen by all tests. Regardless of whether the tests were loaded
before or after the variable was set.

Both optional arguments were created for integrating a third party test suites
or test runners into OpenQA. In such cases the same test module may be
dynamically queued multiple times to execute different test cases within the
third party test suite.

=cut

sub loadtest {
    my ($script, %args) = @_;
    my $casedir = $bmwqemu::vars{CASEDIR};

    unless (-f join('/', $casedir, $script)) {
        warn "loadtest needs a script below $casedir - $script is not\n";
        $script = File::Spec->abs2rel($script, $bmwqemu::vars{CASEDIR});
    }
    unless ($script =~ m,(\w+)/([^/]+)\.pm$,) {
        die "loadtest needs a script to match \\w+/[^/]+.pm\n";
    }
    my $category = $1;
    my $name     = $2;
    my $test;
    my $fullname = "$category-$name";
    # perl code generating perl code is overcool
    # FIXME turn this into a proper eval instead of a generated string
    my $code = "package $name;";
    $code .= "use lib '$casedir/lib';";
    my $basename = dirname($script);
    $code .= "use lib '$casedir/$basename';";
    $code .= "require '$casedir/$script';";
    eval $code;    ## no critic
    if ($@) {
        my $msg = "error on $script: $@";
        bmwqemu::diag($msg);
        die $msg;
    }
    $test             = $name->new($category);
    $test->{script}   = $script;
    $test->{fullname} = $fullname;
    $test->{serial_failures} = $testapi::distri->{serial_failures} // [];

    if (defined $args{run_args}) {
        unless (blessed($args{run_args}) && $args{run_args}->isa('OpenQA::Test::RunArgs')) {
            die 'The run_args must be a sub-class of OpenQA::Test::RunArgs';
        }
        $test->{run_args} = $args{run_args};
        delete $args{run_args};
    }

    my $nr = '';
    while (exists $tests{$fullname . $nr}) {
        # to all perl hardcore hackers: fuck off!
        $nr = $nr eq '' ? 1 : $nr + 1;
        $test->{name} = join("#", $name, $nr);
    }
    if ($args{name}) {
        $test->{name} = $args{name};
    }

    $tests{$fullname . $nr} = $test;

    return unless $test->is_applicable;
    push @testorder, $test;
    bmwqemu::diag("scheduling $test->{name} $script");
}

our $current_test;
our $selected_console;
our $last_milestone;
our $last_milestone_console;

sub set_current_test {
    ($current_test) = @_;
    query_isotovideo(
        'set_current_test',
        $current_test ?
          {
            name      => $current_test->{name},
            full_name => $current_test->{fullname},
          }
        : {});
}

sub write_test_order {

    my @result;
    for my $t (@testorder) {
        push(
            @result,
            {
                name     => $t->{name},
                category => $t->{category},
                flags    => $t->test_flags(),
                script   => $t->{script}});
    }
    bmwqemu::save_json_file(\@result, bmwqemu::result_dir . "/test_order.json");
}

sub make_snapshot {
    my ($sname) = @_;
    bmwqemu::diag("Creating a VM snapshot $sname");
    return query_isotovideo('backend_save_snapshot', {name => $sname});
}

sub load_snapshot {
    my ($sname) = @_;
    bmwqemu::diag("Loading a VM snapshot $sname");
    return query_isotovideo('backend_load_snapshot', {name => $sname});
}

sub run_all {
    my $died      = 0;
    my $completed = 0;
    eval { $completed = autotest::runalltests(); };
    if ($@) {
        warn $@;
        $died = 1;    # test execution died
    }
    eval {
        bmwqemu::save_vars();
        myjsonrpc::send_json($isotovideo, {cmd => 'tests_done', died => $died, completed => $completed});
    };
    close $isotovideo;
    Devel::Cover::report() if Devel::Cover->can('report');
    _exit(0);
}

sub handle_sigterm {
    my ($sig) = @_;

    if ($current_test) {
        bmwqemu::diag("autotest received signal $sig, saving results of current test before exiting");
        $current_test->result('canceled');
        $current_test->save_test_result();
    }
    _exit(1);
}

sub start_process {
    my $child;

    socketpair($child, $isotovideo, AF_UNIX, SOCK_STREAM, PF_UNSPEC)
      or die "socketpair: $!";

    $child->autoflush(1);
    $isotovideo->autoflush(1);

    $process = process(sub {
            close $child;
            $SIG{TERM} = \&handle_sigterm;
            $SIG{INT}  = 'DEFAULT';
            $SIG{HUP}  = 'DEFAULT';
            $SIG{CHLD} = 'DEFAULT';

            cv::init;
            require tinycv;

            $0 = "$0: autotest";
            my $line = <$isotovideo>;
            if (!$line) {
                _exit(0);
            }
            print "GOT $line\n";
            # the backend process might have added some defaults for the backend
            bmwqemu::load_vars();

            run_all;
    })->blocking_stop(1)->separate_err(0)->set_pipes(0)->internal_pipes(0)->start;
    $process->on(collected => sub { bmwqemu::diag "[" . __PACKAGE__ . "] process exited: " . shift->exit_status; });

    close $isotovideo;
    return ($process, $child);
}


# TODO: define use case and reintegrate
sub prestart_hook {
    # run prestart test code before VM is started
    if (-f "$bmwqemu::vars{CASEDIR}/prestart.pm") {
        bmwqemu::diag "running prestart step";
        eval { require $bmwqemu::vars{CASEDIR} . "/prestart.pm"; };
        if ($@) {
            bmwqemu::diag "prestart step FAIL:";
            die $@;
        }
    }
}

# TODO: define use case and reintegrate
sub postrun_hook {
    # run postrun test code after VM is stopped
    if (-f "$bmwqemu::vars{CASEDIR}/postrun.pm") {
        bmwqemu::diag "running postrun step";
        eval { require "$bmwqemu::vars{CASEDIR}/postrun.pm"; };    ## no critic
        if ($@) {
            bmwqemu::diag "postrun step FAIL:";
            warn $@;
        }
    }
}

sub query_isotovideo {
    my ($cmd, $args) = @_;

    # deep copy
    my %json;
    if ($args) {
        %json = %$args;
    }
    $json{cmd} = $cmd;

    # send the command to isotovideo
    myjsonrpc::send_json($isotovideo, \%json);

    # wait for response (if test is paused, this will block until resume)
    my $rsp = myjsonrpc::read_json($isotovideo);

    return $rsp->{ret};
}

sub runalltests {

    die "ERROR: no tests loaded" unless @testorder;

    my $firsttest           = $bmwqemu::vars{SKIPTO} || $testorder[0]->{fullname};
    my $vmloaded            = 0;
    my $snapshots_supported = query_isotovideo('backend_can_handle', {function => 'snapshots'});
    bmwqemu::diag "Snapshots are " . ($snapshots_supported ? '' : 'not ') . "supported";

    write_test_order();

    for my $t (@testorder) {
        my $flags    = $t->test_flags();
        my $fullname = $t->{fullname};

        if (!$vmloaded && $fullname eq $firsttest) {
            if ($bmwqemu::vars{SKIPTO}) {
                if ($bmwqemu::vars{TESTDEBUG}) {
                    load_snapshot('lastgood');
                }
                else {
                    load_snapshot($firsttest);
                }
            }
            $vmloaded = 1;
        }
        if ($vmloaded) {
            my $name = $t->{name};
            bmwqemu::modstart "starting $name $t->{script}";
            $t->start();

            # avoid erasing the good vm snapshot
            if ($snapshots_supported && (($bmwqemu::vars{SKIPTO} || '') ne $fullname) && $bmwqemu::vars{MAKETESTSNAPSHOTS}) {
                make_snapshot($t->{fullname});
            }

            eval { $t->runtest; };
            $t->save_test_result();

            if ($@) {
                my $msg = $@;
                if ($msg !~ /^test.*died/) {
                    # avoid duplicating the message
                    bmwqemu::diag $msg;
                }
                if ($flags->{fatal} || $t->{fatal_failure} || !$snapshots_supported || $bmwqemu::vars{TESTDEBUG}) {
                    bmwqemu::stop_vm();
                    return 0;
                }
                elsif (!$flags->{norollback} && $last_milestone) {
                    load_snapshot('lastgood');
                    $last_milestone->rollback_activated_consoles();
                }
            }
            else {
                if ($snapshots_supported && ($flags->{milestone} || $bmwqemu::vars{TESTDEBUG})) {
                    make_snapshot('lastgood');
                    $last_milestone         = $t;
                    $last_milestone_console = $selected_console;
                }
            }
        }
        else {
            bmwqemu::diag "skipping $fullname";
            $t->skip_if_not_running();
            $t->save_test_result();
        }
    }
    return 1;
}

sub loadtestdir {
    my ($dir) = @_;
    die "need argument \$dir" unless $dir;
    $dir =~ s/^\Q$bmwqemu::vars{CASEDIR}\E\/?//;    # legacy where absolute path is specified
    $dir = join('/', $bmwqemu::vars{CASEDIR}, $dir);    # always load from casedir
    die "'$dir' does not exist!\n" unless -d $dir;
    foreach my $script (glob "$dir/*.pm") {
        loadtest($script);
    }
}

1;

# vim: set sw=4 et:
