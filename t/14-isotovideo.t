#!/usr/bin/perl

use strict;
use warnings;
use autodie ':all';
use Test::More;
use File::Basename;
use File::Path 'remove_tree';
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
    unlink('vars.json') if -e 'vars.json';
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

subtest 'isotovideo with custom git repo parameters specified' => sub {
    chdir($pool_dir);
    unlink('vars.json') if -e 'vars.json';
    mkdir('repo.git') unless -d 'repo.git';
    qx{git init -q --bare repo.git};
    # Ensure the checkout folder does not exist so that git clone tries to
    # create a new checkout on every test run
    remove_tree('repo');
    isotovideo(opts => "casedir=file://$pool_dir/repo.git#foo needles_dir=$data_dir _exit_after_schedule=1");
    is_in_log('git URL.*\<repo\>', 'git repository would be cloned');
    is_in_log('branch.*foo',       'branch in git repository would be checked out');
    is_in_log('No scripts',        'the repo actually has no test definitions');
};

subtest 'productdir variable relative/absolute' => sub {
    chdir($pool_dir);
    unlink('vars.json') if -e 'vars.json';
    isotovideo(opts => "casedir=$data_dir/tests _exit_after_schedule=1 productdir=$data_dir/tests");
    is_in_log('\d* scheduling.*shutdown', 'schedule has been evaluated');
    mkdir('product')     unless -e 'product';
    mkdir('product/foo') unless -e 'product/foo';
    symlink("$data_dir/tests/main.pm", "$pool_dir/product/foo/main.pm") unless -e "$pool_dir/product/foo/main.pm";
    isotovideo(opts => "casedir=$data_dir/tests _exit_after_schedule=1 productdir=product/foo");
    is_in_log('\d* scheduling.*shutdown', 'schedule can still be found');
};

done_testing();
