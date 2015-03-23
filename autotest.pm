package autotest;
use strict;
use bmwqemu;
use basetest;

use File::Basename;
use File::Spec;

our %tests;        # scheduled or run tests
our @testorder;    # for keeping them in order
our $running;      # currently running test or undef

sub loadtest($) {
    my ($script) = @_;
    my $casedir = $bmwqemu::vars{CASEDIR};

    unless (-f join('/', $casedir, $script) ) {
        warn "loadtest needs a script below $casedir\n";
        $script = File::Spec->abs2rel( $script, $bmwqemu::vars{CASEDIR} );
    }
    unless ( $script =~ m,(\w+)/([^/]+)\.pm$, ) {
        die "loadtest needs a script to match \\w+/[^/]+.pm\n";
    }
    my $category = $1;
    my $name     = $2;
    my $test;
    my $fullname = "$category-$name";
    if ( exists $tests{$fullname} ) {
        $test = $tests{$fullname};
        return unless $test->is_applicable;
    }
    else {
        # perl code generating perl code is overcool
        my $code = "package $name;";
        $code .= "use lib '$casedir/lib';";
        my $basename = dirname($script);
        $code .= "use lib '$casedir/$basename';";
        $code .= "require '$casedir/$script';";
        eval $code;
        if ($@) {
            my $msg = "error on $script: $@";
            bmwqemu::diag($msg);
            die $msg;
        }
        $test = $name->new($category);
        $test->{script}   = $script;
        $test->{fullname} = $fullname;
        $tests{$fullname} = $test;

        return unless $test->is_applicable;
        push @testorder, $test;
    }
    bmwqemu::diag "scheduling $name $script";
}

our $current_test;

sub set_current_test($) {
    ($current_test) = @_;
    bmwqemu::save_status();
}

sub write_test_order() {

    my @result;
    for my $t (@testorder) {
        push(
            @result,
            {
                'name'     => ref($t),
                'category' => $t->{category},
                'flags'    => $t->test_flags(),
                'script'   => $t->{script}
            }
        );
    }
    bmwqemu::save_json_file(\@result, bmwqemu::result_dir . "/test_order.json");

}

sub runalltests {
    my $firsttest = $bmwqemu::vars{SKIPTO} || $testorder[0]->{fullname};
    my $vmloaded = 0;

    write_test_order();

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

            # avoid erasing the good vm snapshot
            if ( ( $bmwqemu::vars{SKIPTO} || '') ne $t->{fullname} && $bmwqemu::vars{MAKETESTSNAPSHOTS} ) {
                bmwqemu::make_snapshot( $t->{fullname} );
            }

            eval { $t->runtest; };
            $t->save_test_result();

            if ($@) {

                bmwqemu::diag $@;
                if ( $flags->{fatal} ) {
                    bmwqemu::stop_vm();
                    return 0;
                }
                elsif (!$flags->{norollback} ) {
                    bmwqemu::load_snapshot('lastgood');
                }
            }
            else {
                if ( $flags->{milestone} ) {
                    bmwqemu::make_snapshot('lastgood');
                }
            }
        }
        else {
            bmwqemu::diag "skiping $t->{fullname}";
            $t->skip_if_not_running;
        }
    }
    return 1;
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

1;

# vim: set sw=4 et:
