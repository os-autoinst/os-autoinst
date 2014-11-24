package autotest;
use strict;
use bmwqemu;
use basetest;

use File::Spec;

our %tests;        # scheduled or run tests
our @testorder;    # for keeping them in order
our $running;      # currently running test or undef

sub loadtest($) {
    my $script = shift;
    return unless $script =~ /.*\/(\w+)\/(.+)\.pm$/;
    my $category = $1;
    my $name     = $2;
    my $test;
    my $fullname = "$category-$name";
    if ( exists $tests{$fullname} ) {
        $test = $tests{$fullname};
        return unless $test->is_applicable;
    }
    else {
        eval "package $name; use lib \$bmwqemu::vars{CASEDIR}.'/lib'; require \$script;";
        if ($@) {
            my $msg = "error on $script: $@";
            bmwqemu::diag($msg);
            die $msg;
        }
        $test = $name->new($category);
        $test->{script}   = File::Spec->abs2rel( $script, $bmwqemu::vars{CASEDIR} );
        $test->{fullname} = $fullname;
        $tests{$fullname} = $test;

        return unless $test->is_applicable;
        push @testorder, $test;
    }
    bmwqemu::diag "scheduling $name $script";
}

sub runalltests {
    my $firsttest = $bmwqemu::vars{SKIPTO} || $testorder[0]->{fullname};
    my $vmloaded = 0;

    for my $t (@testorder) {
        my $flags = $t->test_flags();

        if ( !$vmloaded && $t->{fullname} eq $firsttest ) {
            bmwqemu::load_snapshot($firsttest) if $bmwqemu::vars{SKIPTO};
            $vmloaded = 1;
        }
        if ($vmloaded) {
            my $name = ref($t);
            bmwqemu::modstart "starting $name $t->{script}";
            $t->start();
            bmwqemu::save_results( results() );

            # avoid erasing the good vm snapshot
            if ( ( $bmwqemu::vars{'SKIPTO'} || '') ne $t->{'fullname'} && $bmwqemu::vars{MAKETESTSNAPSHOTS} ) {
                bmwqemu::make_snapshot( $t->{'fullname'} );
            }

            eval { $t->runtest; };
            if ($@) {

                # Do some cleaning after case fail.
                # Like don't find a needle.
                $t->post_failure;
                bmwqemu::diag "test $name failed: $@\n";
                if ( $flags->{'fatal'} ) {
                    bmwqemu::stop_vm();
                    die $@;
                }
                elsif (!$flags->{'norollback'} ) {
                    bmwqemu::load_snapshot('lastgood');
                }
            }
            else {
                if ( $flags->{'milestone'} ) {
                    bmwqemu::make_snapshot('lastgood');
                }
            }
        }
        else {
            bmwqemu::diag "skiping $t->{fullname}";
            $t->skip_if_not_running;
        }
    }
}

sub loadtestdir($) {
    my $dir = shift;
    $dir =~ s/^\Q$bmwqemu::vars{CASEDIR}\E\/?//; # legacy where absolute path is specified
    $dir = join('/', $bmwqemu::vars{CASEDIR}, $dir); # always load from casedir
    die "$dir does not exist!\n" unless -d $dir;
    foreach my $script (<$dir/*.pm>) {
        loadtest($script);
    }
}

sub results() {
    my $results = [];
    for my $t (@testorder) {
        push @$results, $t->json();
    }
    return $results;
}

1;

# vim: set sw=4 et:
