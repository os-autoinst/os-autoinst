#!/usr/bin/perl

# Copyright (C) 2017-2019 SUSE LLC
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
use Test::Exception;
use File::Temp 'tempdir';
use File::Basename;
use File::Path 'make_path';
use Cwd 'abs_path';
use Mojo::JSON;    # booleans
use Cpanel::JSON::XS ();

my $toplevel_dir = abs_path(dirname(__FILE__) . '/..');
my $data_dir     = "$toplevel_dir/t/data";

sub create_vars {
    my $data = shift;
    open(my $varsfh, '>', 'vars.json') || BAIL_OUT('can not create vars.json');
    my $json = Cpanel::JSON::XS->new->pretty->canonical;
    print $varsfh $json->encode($data);
    close($varsfh);
}

sub read_vars {
    local $/;
    open(my $varsfh, '<', 'vars.json') || BAIL_OUT('can not open vars.json for reading');
    my $ret;
    eval { $ret = Cpanel::JSON::XS->new->relaxed->decode(<$varsfh>); };
    die "parse error in vars.json:\n$@" if $@;
    close($varsfh);
    return $ret;
}

subtest 'CASEDIR is mandatory' => sub {
    my $dir = '/var/lib/openqa';
    create_vars({DISTRI => 'test'});

    eval {
        use bmwqemu ();
        bmwqemu::init;
        bmwqemu::ensure_valid_vars();
    };
    like($@, qr(CASEDIR variable not set.*), 'bmwqemu refuses to init');


    my %vars = %{read_vars()};
    is($vars{DISTRI}, 'test', 'DISTRI unchanged by init call');
    ok(!$vars{CASEDIR}, 'CASEDIR not set');
};

subtest 'save_vars' => sub {
    my $dir = "$data_dir/tests";
    create_vars({CASEDIR => $dir, _SECRET_TEST => 'my_credentials'});
    $bmwqemu::openqa_default_share = $data_dir;

    eval {
        use bmwqemu ();
        bmwqemu::init;
        bmwqemu::save_vars();
    };
    ok(!$@, 'init successful');

    my %vars = %{read_vars()};
    is($vars{_SECRET_TEST}, 'my_credentials', '_SECRET_TEST unchanged');
    is($vars{CASEDIR},      $dir,             'CASEDIR unchanged');
};

subtest 'save_vars no_secret' => sub {
    my $dir = "$data_dir/tests";
    create_vars({CASEDIR => $dir, _SECRET_TEST => 'my_credentials'});
    $bmwqemu::openqa_default_share = $data_dir;

    eval {
        use bmwqemu ();
        bmwqemu::init;
        bmwqemu::save_vars(no_secret => 1);
    };
    ok(!$@, 'init successful');

    my %vars = %{read_vars()};
    ok(!$vars{_SECRET_TEST}, '_SECRET_TEST not written to vars.json');
    is($vars{CASEDIR}, $dir, 'CASEDIR unchanged');
};

subtest 'HDD variables sanity check' => sub {
    use bmwqemu ();
    %bmwqemu::vars = (NUMDISKS => 1, HDD_1 => 'foo.qcow2', PUBLISH_HDD_1 => 'bar.qcow2');
    ok(bmwqemu::_check_publish_vars, 'one HDD for reading, one for publishing is ok');
    $bmwqemu::vars{PUBLISH_HDD_1} = 'foo.qcow2';
    throws_ok { bmwqemu::_check_publish_vars } qr/HDD_1 also specified in PUBLISH/, 'overwriting source HDD is prevented';
};

done_testing;

END {
    unlink 'vars.json';
}

1;
