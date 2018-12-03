#!/usr/bin/perl
# Copyright (C) 2018 SUSE LLC
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


use strict;
use warnings;
use Test::More;
use Test::Warnings;
use Try::Tiny;
use File::Basename;
use Cwd 'abs_path';
use Mojo::File;

# optional but very useful
eval 'use Test::More::Color';
eval 'use Test::More::Color "foreground"';

my $toplevel_dir = abs_path(dirname(__FILE__) . '/..');
my $data_dir     = "$toplevel_dir/t/data/";
my $pool_dir     = "$toplevel_dir/t/pool/";

chdir($pool_dir);

# Test QEMU_APPEND option with:
# * version: '-version'
# * list machines: '-M ?'
# * multiple options: '-M ? -version'
# * invalid option: '-broken option'
# Note: no option starts a full qemu test
subtest qemu_append_option => sub {

    # Print version
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
   "QEMU_APPEND" : "version"
}
EOV
    close($var);
    # call isotovideo with QEMU_APPEND
    system("perl $toplevel_dir/isotovideo -d qemu_disable_snapshots=1 2>&1 | tee autoinst-log.txt");
    is(system('grep -q -e "-version" autoinst-log.txt'),                                     0, '-version option added');
    is(system('grep -q "QEMU emulator version" autoinst-log.txt'),                           0, 'QEMU version printed');
    is(system('grep -q "Fabrice Bellard and the QEMU Project developers" autoinst-log.txt'), 0, 'Copyright printed');
    isnt(system('grep -q -e ": invalid option" autoinst-log.txt'), 0, 'no invalid option detected');

    # List machines
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
   "VERSION" : "1",
   "QEMU_APPEND" : "M ?"
}
EOV
    close($var);
    # call isotovideo with QEMU_APPEND, to list machines
    system("perl $toplevel_dir/isotovideo -d qemu_disable_snapshots=1 2>&1 | tee autoinst-log.txt");
    is(system('grep -q -e "-M ?" autoinst-log.txt'),                 0, '-M ? option added');
    is(system('grep -q "Supported machines are:" autoinst-log.txt'), 0, 'Supported machines listed');
    isnt(system('grep -q -e ": invalid option" autoinst-log.txt'), 0, 'no invalid option detected');

    # Multiple options
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
   "VERSION" : "1",
   "QEMU_APPEND" : "M ? -version"
}
EOV
    close($var);
    # call isotovideo with QEMU_APPEND, with version
    system("perl $toplevel_dir/isotovideo -d qemu_disable_snapshots=1 2>&1 | tee autoinst-log.txt");
    is(system('grep -q -e "-version" autoinst-log.txt'),                                     0, '-version option added');
    is(system('grep -q "QEMU emulator version" autoinst-log.txt'),                           0, 'QEMU version printed');
    is(system('grep -q "Fabrice Bellard and the QEMU Project developers" autoinst-log.txt'), 0, 'Copyright printed');
    isnt(system('grep -q -e ": invalid option" autoinst-log.txt'), 0, 'no invalid option detected');

    # Invalid option
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
   "VERSION" : "1",
   "QEMU_APPEND" : "broken option"
}
EOV
    close($var);

    # call isotovideo with QEMU_APPEND, with a broken option
    system("perl $toplevel_dir/isotovideo -d qemu_disable_snapshots=1 2>&1 | tee autoinst-log.txt");
    is(system('grep -q -e "-broken option" autoinst-log.txt'),          0, '-broken option added');
    is(system('grep -q -e "-broken: invalid option" autoinst-log.txt'), 0, 'invalid option detected');

};

done_testing();
