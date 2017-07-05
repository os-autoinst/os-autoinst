#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Try::Tiny;
use File::Basename;
use Cwd 'abs_path';
use Mojo::File;
use JSON 'from_json';

# optional but very useful
eval 'use Test::More::Color';                 ## no critic
eval 'use Test::More::Color "foreground"';    ## no critic

my $toplevel_dir = abs_path(dirname(__FILE__) . '/..');
my $data_dir     = "$toplevel_dir/t/data/";
my $pool_dir     = "$toplevel_dir/t/pool/";

chdir($pool_dir);
open(my $var, '>', 'vars.json');
print $var <<EOV;
{
   "ARCH" : "i386",
   "BACKEND" : "qemu",
   "QEMU" : "i386",
   "QEMU_NO_KVM" : "1",
   "QEMU_NO_TABLET" : "1",
   "QEMU_NO_FDC_SET" : "1",
   "CASEDIR" : "$data_dir/tests",
   "PRJDIR"  : "$data_dir",
   "ISO" : "$data_dir/Core-7.2.iso",
   "CDMODEL" : "ide-cd",
   "HDDMODEL" : "ide-drive",
   "VERSION" : "1",
}
EOV
close($var);
# create screenshots
open($var, '>', 'live_log');
close($var);
system("perl $toplevel_dir/isotovideo -d 2>&1 | tee autoinst-log.txt");
is(system('grep -q "\d*: EXIT 0" autoinst-log.txt'), 0, 'test executed fine');

my $ignore_results_re = qr/fail/;
for my $result (grep { $_ !~ $ignore_results_re } glob("testresults/result*.json")) {
    my $json = from_json(Mojo::File->new($result)->slurp);
    is($json->{result}, 'ok', "Result in $result is ok") or BAIL_OUT("$result failed");
}

for my $result (glob("testresults/result*fail*.json")) {
    my $json = from_json(Mojo::File->new($result)->slurp);
    is($json->{result}, 'fail', "Result in $result is fail") or BAIL_OUT("$result failed");
}

subtest 'Assert screen failure' => sub {
    plan tests => 1;
    open my $ifh, '<', 'autoinst-log.txt';
    my $regexp = qr /(?<=no candidate needle with tag\(s\)) '(no_tag, no_tag2|no_tag3)'/;
    my $count  = 0;
    while (<$ifh>) {
        $count++ if $_ =~ $regexp;
    }
    close $ifh;

    is($count, 2, 'Assert screen failures');
};

open($var, '>', 'vars.json');
print $var <<EOV;
{
   "ARCH" : "i386",
   "BACKEND" : "qemu",
   "QEMU" : "i386",
   "QEMU_NO_KVM" : "1",
   "QEMU_NO_TABLET" : "1",
   "QEMU_NO_FDC_SET" : "1",
   "CASEDIR" : "$data_dir/tests",
   "PRJDIR"  : "$data_dir",
   "ISO" : "$data_dir/Core-7.2.iso",
   "CDMODEL" : "ide-cd",
   "HDDMODEL" : "ide-drive",
   "INTEGRATION_TESTS" : "1",
   "VERSION" : "1",
}
EOV

system("perl $toplevel_dir/isotovideo -d 2>&1 | tee autoinst-log.txt");
isnt(system('grep -q "assert_screen_fail_test" autoinst-log.txt'), 0, 'assert screen test not scheduled');
is(system('grep -q "isotovideo done" autoinst-log.txt'), 0, 'isotovideo is done');
is(system('grep -q "EXIT 0" autoinst-log.txt'),          0, 'Test finished as expected');

done_testing();
