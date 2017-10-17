#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Basename;
use Cwd 'abs_path';

my $toplevel_dir = abs_path(dirname(__FILE__) . '/..');
my $data_dir     = "$toplevel_dir/t/data/";
my $pool_dir     = "$toplevel_dir/t/pool/";

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
system("perl $toplevel_dir/isotovideo -d 2>&1 | tee autoinst-log.txt");
is(system('grep -q "\d*: EXIT 1" autoinst-log.txt'),              0, 'test exited early as requested');
is(system('grep -q "\d* scheduling.*shutdown" autoinst-log.txt'), 0, 'schedule has been evaluated');

done_testing();
