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
use Test::More;
use File::Temp 'tempdir';
use File::Path 'make_path';
use JSON;

BEGIN {
    unshift @INC, '..';
}

sub create_vars {
    my $data = shift;
    open(my $varsfh, '>', 'vars.json') || BAIL_OUT('can not create vars.json');
    my $json = JSON->new->pretty->canonical;
    print $varsfh $json->encode($data);
    close($varsfh);
}

sub read_vars {
    local $/;
    open(my $varsfh, '<', 'vars.json') || BAIL_OUT('can not open vars.json for reading');
    my $ret;
    eval { $ret = JSON->new->relaxed->decode(<$varsfh>); };
    die "parse error in vars.json:\n$@" if $@;
    close($varsfh);
    return $ret;
}

subtest 'CASEDIR is mandatory' => sub {
    my $dir = '/var/lib/openqa';
    create_vars({DISTRI => 'test', PRJDIR => $dir});

    eval {
        use bmwqemu ();
        bmwqemu::init;
    };
    like($@, qr(CASEDIR variable not set in vars.json.*), 'bmwqemu refuses to init');


    my %vars = %{read_vars()};
    is($vars{DISTRI}, 'test', 'DISTRI unchanged by init call');
    ok(!$vars{CASEDIR}, 'CASEDIR not set');
    is($vars{PRJDIR}, $dir, 'PRJDIR unchanged');
};

subtest 'test PRJDIR default' => sub {
    my $dir = '/var/lib/openqa/share/tests/test';
    create_vars({CASEDIR => $dir});

    eval {
        use bmwqemu ();
        bmwqemu::init;
    };
    ok(!$@, 'init successful');

    my %vars = %{read_vars()};
    ok(!$vars{DISTRI}, 'DISTRI not supplied and not set');
    is($vars{CASEDIR}, $dir, 'CASEDIR unchanged');
    is($vars{PRJDIR}, '/var/lib/openqa/share', 'PRJDIR set to default');
};

subtest 'test CASEDIR not under PRJDIR default' => sub {
    my $dir = '/tmp/some/dir/tests/test';
    create_vars({CASEDIR => $dir});

    eval {
        use bmwqemu ();
        bmwqemu::init;
    };
    ok($@, 'bmwqemu init failed');

    my %vars = %{read_vars()};
    ok(!$vars{DISTRI}, 'DISTRI not supplied and not set');
    is($vars{CASEDIR}, $dir, 'CASEDIR unchanged');
    ok(!$vars{PRJDIR}, 'PRJDIR not supplied and not set');
};

done_testing;

END {
    unlink 'vars.json';
}

1;
