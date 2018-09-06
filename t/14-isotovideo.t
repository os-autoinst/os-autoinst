#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Basename;
use File::Path;
use Cwd 'abs_path';

my $toplevel_dir = abs_path(dirname(__FILE__) . '/..');
my $data_dir     = "$toplevel_dir/t/data";
my $pool_dir     = "$toplevel_dir/t/pool";

sub isotovideo {
    my (%args) = @_;
    $args{opts} //= '';
    system("perl $toplevel_dir/isotovideo -d $args{opts} 2>&1 | tee autoinst-log.txt");
    is(system('grep -q "\d*: EXIT 1" autoinst-log.txt'), 0, $args{end_test_str} ? $args{end_test_str} : 'isotovideo run exited as expected');
}

sub is_in_log {
    my ($regex, $msg) = @_;
    is(system("grep -q \"$regex\" autoinst-log.txt"), 0, $msg);
}

subtest 'standalone isotovideo without vars.json file and only command line parameters' => sub {
    chdir($pool_dir);
    unlink('vars.json');
    isotovideo(opts => "casedir=$data_dir/tests schedule=foo,bar/baz _exit_after_schedule=1");
    is_in_log('scheduling.*foo',     'requested modules are run as part of enforced scheduled');
    is_in_log('scheduling.*bar/baz', 'requested modules in subdirs are scheduled');
};

subtest 'standard tests based on simple vars.json file' => sub {
    chdir($pool_dir);
    open(my $var, '>', 'vars.json');
    print $var <<EOV;
{
   "CASEDIR" : "$data_dir/tests",
   "PRJDIR"  : "$data_dir",
   "_EXIT_AFTER_SCHEDULE" : 1,
}
EOV
    close($var);
    isotovideo;
    is_in_log('\d*: EXIT 1',              'test exited early as requested');
    is_in_log('\d* scheduling.*shutdown', 'schedule has been evaluated');
};

done_testing();
