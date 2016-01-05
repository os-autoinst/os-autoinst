# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2015 SUSE LLC
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
use basetest;

use File::Basename;
use File::Spec;

our %tests;        # scheduled or run tests
our @testorder;    # for keeping them in order
our $running;      # currently running test or undef

sub loadtest {
    my ($script) = @_;
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
    if (exists $tests{$fullname}) {
        $test = $tests{$fullname};
        return unless $test->is_applicable;
    }
    else {
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
        $tests{$fullname} = $test;

        return unless $test->is_applicable;
        push @testorder, $test;
    }
    bmwqemu::diag "scheduling $name $script";
}

our $current_test;

sub set_current_test {
    ($current_test) = @_;
    bmwqemu::save_status();
}

sub write_test_order() {

    my @result;
    for my $t (@testorder) {
        push(
            @result,
            {
                name     => ref($t),
                category => $t->{category},
                flags    => $t->test_flags(),
                script   => $t->{script}});
    }
    bmwqemu::save_json_file(\@result, bmwqemu::result_dir . "/test_order.json");

}

sub make_snapshot {
    my ($sname) = @_;
    bmwqemu::diag("Creating a VM snapshot $sname");
    return $bmwqemu::backend->save_snapshot({name => $sname});
}

sub load_snapshot {
    my ($sname) = @_;
    bmwqemu::diag("Loading a VM snapshot $sname");
    return $bmwqemu::backend->load_snapshot({name => $sname});
}

sub runalltests {

    die "ERROR: no tests loaded" unless @testorder;

    my $firsttest           = $bmwqemu::vars{SKIPTO} || $testorder[0]->{fullname};
    my $vmloaded            = 0;
    my $snapshots_supported = $bmwqemu::backend->can_handle({function => 'snapshots'})->{ret};

    write_test_order();

    for my $t (@testorder) {
        my $flags = $t->test_flags();

        if (!$vmloaded && $t->{fullname} eq $firsttest) {
            load_snapshot($firsttest) if $bmwqemu::vars{SKIPTO};
            $vmloaded = 1;
        }
        if ($vmloaded) {
            my $name = ref($t);
            bmwqemu::modstart "starting $name $t->{script}";
            $t->start();

            # avoid erasing the good vm snapshot
            if ($snapshots_supported && (($bmwqemu::vars{SKIPTO} || '') ne $t->{fullname}) && $bmwqemu::vars{MAKETESTSNAPSHOTS}) {
                make_snapshot($t->{fullname});
            }

            eval { $t->runtest; };
            $t->save_test_result();

            if ($@) {

                bmwqemu::diag $@;
                if ($flags->{fatal} || !$snapshots_supported) {
                    bmwqemu::stop_vm();
                    return 0;
                }
                elsif (!$flags->{norollback}) {
                    load_snapshot('lastgood');
                }
            }
            else {
                if ($snapshots_supported && $flags->{milestone}) {
                    make_snapshot('lastgood');
                }
            }
        }
        else {
            bmwqemu::diag "skiping $t->{fullname}";
            $t->skip_if_not_running;
            $t->save_test_result();
        }
    }
    return 1;
}

sub loadtestdir {
    my $dir = shift;
    $dir =~ s/^\Q$bmwqemu::vars{CASEDIR}\E\/?//;    # legacy where absolute path is specified
    $dir = join('/', $bmwqemu::vars{CASEDIR}, $dir);    # always load from casedir
    die "$dir does not exist!\n" unless -d $dir;
    foreach my $script (glob "$dir/*.pm") {
        loadtest($script);
    }
}

1;

# vim: set sw=4 et:
