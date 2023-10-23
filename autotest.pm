# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package autotest;

use Mojo::Base -strict, -signatures;

use bmwqemu;
use Exporter 'import';
use File::Basename;
use Socket;
use IO::Handle;
use POSIX '_exit';
use Carp qw();
use cv;
use signalblocker;
use Scalar::Util 'blessed';
use Mojo::IOLoop::ReadWriteProcess 'process';
use Mojo::IOLoop::ReadWriteProcess::Session 'session';
use Mojo::File qw(path);
use File::Glob qw(bsd_glob);

our @EXPORT_OK = qw(loadtest $selected_console $last_milestone_console query_isotovideo);

our %tests;    # scheduled or run tests
our @testorder;    # for keeping them in order
our $isotovideo;
our $process;
our $tests_running = 0;
=head1 Introduction

OS Autoinst decides which test modules to run based on a distribution specific
script called main.pm. This is either located in $vars{PRODUCTDIR} or
$vars{CASEDIR} (e.g. <distribution>/products/<product>/main.pm).

Wheels can be used to add functionality from other repositories. If a file
`wheels.yaml` is present the specified git repositories are cloned before tests
are run. $vars{WHEELS_DIR} defaults to the working directory of `isotovideo`
if not set explicitly and determines where wheels are stored.

This script does not actually run the tests, but queues them to be run by
autotest.pm. A test is queued by calling the loadtest function which is also
located in autotest.pm. The test modules are executed in the same order that
loadtest is called.

=cut

sub find_script ($script) {
    my $wheels_dir = $bmwqemu::vars{WHEELS_DIR} // Cwd::getcwd;
    if (defined(my $wheel = bsd_glob "$wheels_dir/*/tests/$script")) {
        return $wheel;
    }
    my $casedir = $bmwqemu::vars{CASEDIR};
    my $script_override_path = join('/', $bmwqemu::vars{ASSETDIR} // '', 'other', $script);
    if (-f $script_override_path) {
        bmwqemu::diag("Found override test module for $script: $script_override_path");
        return path($script_override_path)->to_rel($casedir);
    }
    elsif (!-f join('/', $casedir, $script)) {
        warn "loadtest needs a script below $casedir - $script is not\n";
        return path($script)->to_rel($casedir);
    }
    return "$casedir/$script";
}

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

Prefers test module files found in the openQA asset folder "other/" over
corresponding files within the "CASEDIR" tree to allow temporary overrides,
e.g. by making use of the openQA asset download feature.

=cut

sub _debug_python_version () {
    state $python_loaded = 0;
    return if $python_loaded++;
    my $code = <<~'EOM';
    use Inline::Python;
    return Inline::Python::py_eval('__import__("sys").version', 0);
    EOM
    my $debug = eval $code;
    bmwqemu::diag "Using python version " . $debug;
}

sub loadtest ($script, %args) {
    no utf8;    # Inline Python fails on utf8, so let's exclude it here
    my $casedir = $bmwqemu::vars{CASEDIR};
    my $script_path = find_script($script);
    my ($name, $category) = parse_test_path($script_path);
    my $test;
    my $fullname = "$category-$name";
    # perl code generating perl code is overcool
    my $code = "package $name;";
    $code .= "use lib '.';" unless path($casedir)->is_abs;
    $code .= "use lib '$casedir/lib';";
    my $basename = dirname($script_path);
    $code .= "use lib '$basename';";
    die "Unsupported file extension for '$script'" unless $script =~ /\.p[my]/;
    my $is_python = 0;
    if ($script =~ m/\.pm$/) {
        $code .= "require '$script_path';";
    }
    elsif ($script =~ m/\.py$/) {
        _debug_python_version();
        # Adding the include path of os-autoinst into python context
        my $inc = File::Basename::dirname(__FILE__);
        my $script_dir = path(File::Basename::dirname($script_path))->to_abs;
        $code .= <<~"EOM";
            use base 'basetest';
            use Inline::Python qw(py_eval py_bind_func py_study_package);
            py_eval(<<'END_OF_PYTHON_CODE');
            import sys
            sys.path.append("$inc")
            sys.path.append("$script_dir")
            import $name
            END_OF_PYTHON_CODE
            # Bind the python functions to the perl $name package
            my %info = py_study_package("$name");
            for my \$func (\@{ \$info{functions} }) {
                py_bind_func("${name}::\$func", "$name", \$func);
            }
            EOM
        $is_python = 1;
    }
    eval $code;
    if (my $err = $@) {
        if ($is_python) {
            eval "use Inline Python => 'sys.stderr.flush()';";
            bmwqemu::fctwarn("Unable to flush Python's stderr, error message from Python might be missing: $@") if $@;    # uncoverable statement
        }
        my $msg = "error on $script: $err";
        bmwqemu::fctwarn($msg);
        bmwqemu::serialize_state(component => 'tests', msg => "unable to load $script, check the log for the cause (e.g. syntax error)");
        die $msg;
    }
    $test = $name->new($category);
    $test->{script} = $script;
    $test->{fullname} = $fullname;
    $test->{serial_failures} = $testapi::distri->{serial_failures} // [];
    $test->{autoinst_failures} = $testapi::distri->{autoinst_failures} // [];

    if (defined $args{run_args}) {
        unless (blessed($args{run_args}) && $args{run_args}->isa('OpenQA::Test::RunArgs')) {
            die 'The run_args must be a sub-class of OpenQA::Test::RunArgs';
        }

        die 'run_args is not supported in Python test modules.' if $is_python;

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

    # Test schedule may change at runtime. Update test_order.json to notify
    # the OpenQA server of the change.
    write_test_order() if $tests_running;
    bmwqemu::diag("scheduling $test->{name} $script");
}

our $current_test;
our $selected_console;
our $last_milestone;
our $last_milestone_console;

sub parse_test_path ($script_path) {
    unless ($script_path =~ m,(\w+)/([^/]+)\.p[my]$,) {
        die "loadtest: script path '$script_path' does not match required pattern \\w.+/[^/]+.p[my]\n";
    }
    my $category = $1;
    my $name = $2;
    if ($category ne 'other') {
        # show full folder hierarchy as category for non-sideloaded tests
        my $pattern = qr,(tests/[^/]+/)?tests/([\w/]+)/([^/]+)\.p[my]$,;
        if ($script_path =~ $pattern) {
            $category = $2;
        }
    }
    return ($name, $category);
}

sub set_current_test ($test) {
    $current_test = $test;
    query_isotovideo(
        'set_current_test',
        $current_test ?
          {
            name => $current_test->{name},
            full_name => $current_test->{fullname},
          }
        : {});
}

sub write_test_order () {
    my @result;
    for my $t (@testorder) {
        push(
            @result,
            {
                name => $t->{name},
                category => $t->{category},
                flags => $t->test_flags(),
                script => $t->{script}});
    }
    bmwqemu::save_json_file(\@result, bmwqemu::result_dir . "/test_order.json");
}

sub make_snapshot ($sname) {
    bmwqemu::diag("Creating a VM snapshot $sname");
    return query_isotovideo('backend_save_snapshot', {name => $sname});
}

sub load_snapshot ($sname) {
    bmwqemu::diag("Loading a VM snapshot $sname");
    my $command = query_isotovideo('backend_load_snapshot', {name => $sname});
    # On VMware VNC console needs to be re-selected after snapshot revert,
    # so the screen is refreshed. Same with serial console.
    return unless ($command // '') eq 'vmware_fixup';
    testapi::select_console('sut');
    query_isotovideo('backend_stop_serial_grab');
    query_isotovideo('backend_start_serial_grab');
}

sub _terminate () {
    close $isotovideo;    # uncoverable statement
    Devel::Cover::report() if Devel::Cover->can('report');    # uncoverable statement
    _exit(0);    # uncoverable statement
}

sub run_all () {
    my $died = 0;
    my $completed = 0;
    $tests_running = 1;
    eval { $completed = autotest::runalltests(); };
    if ($@) {
        warn $@;
        $died = 1;    # test execution died
    }
    eval {
        bmwqemu::save_vars(no_secret => 1);
        myjsonrpc::send_json($isotovideo, {cmd => 'tests_done', died => $died, completed => $completed});
    };
    _terminate;
}

sub handle_sigterm ($sig) {
    if ($current_test) {
        bmwqemu::diag("autotest received signal $sig, saving results of current test before exiting");
        $current_test->result('canceled');
        $current_test->save_test_result();
    }
    _exit(1);
}

sub start_process () {
    my $child;
    socketpair($child, $isotovideo, AF_UNIX, SOCK_STREAM, PF_UNSPEC)
      or die "socketpair: $!";

    $child->autoflush(1);
    $isotovideo->autoflush(1);

    $process = process(sub {
            close $child;
            $SIG{TERM} = \&handle_sigterm;
            $SIG{INT} = 'DEFAULT';
            $SIG{HUP} = 'DEFAULT';
            $SIG{CHLD} = 'DEFAULT';

            my $signal_blocker = signalblocker->new;
            cv::init;
            require tinycv;
            tinycv::create_threads();
            undef $signal_blocker;

            $0 = "$0: autotest";
            my $line = <$isotovideo>;
            if (!$line) {
                _exit(0);
            }
            print "GOT $line\n";
            # the backend process might have added some defaults for the backend
            bmwqemu::load_vars();

            run_all;
        },
        sleeptime_during_kill => 0.1,
        total_sleeptime_during_kill => 5,
        blocking_stop => 1,
        separate_err => 0,
        set_pipes => 0,
        internal_pipes => 0)->start;
    $process->on(collected => sub { bmwqemu::diag "[" . __PACKAGE__ . "] process exited: " . shift->exit_status; });

    close $isotovideo;
    return ($process, $child);
}

sub query_isotovideo ($cmd, $args = undef) {
    # deep copy
    my %json;
    if ($args) {
        %json = %$args;
    }
    $json{cmd} = $cmd;

    die "isotovideo is not initialized. Ensure that you only call test API functions from test modules, not schedule code\n" unless defined $isotovideo;
    myjsonrpc::send_json($isotovideo, \%json);

    # wait for response (if test is paused, this will block until resume)
    my $rsp = myjsonrpc::read_json($isotovideo);

    return $rsp->{ret};
}

sub croak ($command, $error) {
    # possibly pause and ignore failure …
    return bmwqemu::diag "ignoring failure via developer mode: $error"
      if autotest::pause_on_failure("$command failed: $error", $command)->{ignore_failure};

    # … or escalate the failure as usual via croak
    local $Carp::CarpLevel = 2;    # omit this helper function in the trace
    Carp::croak $error;
}

my $failed_command;
sub pause_on_failure ($reason, $command = undef) {
    # avoid handling a failing command again (via the die handler) after the test execution has been resumed
    if (!defined $command && $failed_command) {
        undef $failed_command;
        return {};
    }
    $failed_command = $command;

    # hang until the user resumes if supposed to pause on failures via developer mode
    my $rsp = autotest::query_isotovideo(pause_test_execution => {due_to_failure => 1, reason => $reason});
    $rsp = {} unless ref $rsp eq 'HASH';
    undef $failed_command if $rsp->{ignore_failure};
    return $rsp;
}

sub runalltests () {
    die "ERROR: no tests loaded" unless @testorder;

    my $firsttest = $bmwqemu::vars{SKIPTO} || $testorder[0]->{fullname};
    my $vmloaded = 0;
    my $snapshots_supported = query_isotovideo('backend_can_handle', {function => 'snapshots'});
    bmwqemu::diag "Snapshots are " . ($snapshots_supported ? '' : 'not ') . "supported";

    write_test_order();

    for (my $testindex = 0; $testindex <= $#testorder; $testindex++) {
        my $t = $testorder[$testindex];
        my $flags = $t->test_flags();
        my $fullname = $t->{fullname};

        if (!$vmloaded && $fullname eq $firsttest) {
            load_snapshot($bmwqemu::vars{TESTDEBUG} ? 'lastgood' : $firsttest) if $bmwqemu::vars{SKIPTO};
            $vmloaded = 1;
        }
        if (!$vmloaded) {
            bmwqemu::diag "skipping $fullname";
            $t->skip_if_not_running();
            $t->save_test_result();
            next;
        }

        my $name = $t->{name};
        bmwqemu::modstate "starting $name $t->{script}";
        $t->start();

        # avoid erasing the good vm snapshot
        if ($snapshots_supported && (($bmwqemu::vars{SKIPTO} || '') ne $fullname) && $bmwqemu::vars{MAKETESTSNAPSHOTS}) {
            make_snapshot($t->{fullname});
        }

        eval { $t->runtest; };
        my $error = $@;    # save $@, it might be overwritten
        $t->save_test_result();
        my $next_test = $testorder[$testindex + 1];

        if ($error) {
            my $msg = $error;
            if ($msg !~ /^test.*died/) {
                # avoid duplicating the message
                bmwqemu::diag $msg;
            }
            if ($bmwqemu::vars{DUMP_MEMORY_ON_FAIL}) {
                query_isotovideo('backend_save_memory_dump', {filename => $fullname});
            }
            if ($t->{fatal_failure} || $flags->{fatal} || (!exists $flags->{fatal} && !$snapshots_supported) || $bmwqemu::vars{TESTDEBUG}) {
                my $reason = ($t->{fatal_failure} || $flags->{fatal})
                  ? 'after a fatal test failure'
                  : ($bmwqemu::vars{TESTDEBUG}
                    ? 'because TESTDEBUG has been set'
                    : 'because snapshotting is disabled/unavailable and "fatal => 0" has NOT been set explicitly');
                bmwqemu::diag "stopping overall test execution $reason";
                bmwqemu::stop_vm();
                return 0;
            }
            elsif (defined $next_test && !$flags->{no_rollback} && $last_milestone) {
                load_snapshot('lastgood');
                $next_test->record_resultfile('Snapshot', "Loaded snapshot because '$name' failed", result => 'ok');
                $last_milestone->rollback_activated_consoles();
            }
        }
        else {
            if (defined $next_test && !$flags->{no_rollback} && $last_milestone && $flags->{always_rollback}) {
                load_snapshot('lastgood');
                $next_test->record_resultfile('Snapshot', "Loaded snapshot after '$name' (always_rollback)", result => 'ok') if $next_test;
                $last_milestone->rollback_activated_consoles();
            }
            my $makesnapshot = $bmwqemu::vars{TESTDEBUG};
            # Only make a snapshot if there is a next test and it's not a fatal milestone
            if (defined $next_test) {
                my $nexttestflags = $next_test->test_flags();
                $makesnapshot ||= $flags->{milestone} && !($nexttestflags->{milestone} && $nexttestflags->{fatal});
            }
            if ($snapshots_supported && $makesnapshot) {
                make_snapshot('lastgood');
                $last_milestone = $t;
                $last_milestone_console = $selected_console;
            }
        }
    }
    return 1;
}

sub loadtestdir ($dir) {
    die "need argument \$dir" unless $dir;
    $dir =~ s/^\Q$bmwqemu::vars{CASEDIR}\E\/?//;    # legacy where absolute path is specified
    $dir = join('/', $bmwqemu::vars{CASEDIR}, $dir);    # always load from casedir
    die "'$dir' does not exist!\n" unless -d $dir;
    foreach my $script (glob "$dir/*.pm") {
        loadtest($script);
    }
}

1;
