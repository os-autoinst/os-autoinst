# Copyright 2022 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package OpenQA::Isotovideo::Runner;
use Mojo::Base -base, -signatures;

use OpenQA::Isotovideo::Utils qw(checkout_git_repo_and_branch checkout_git_refspec);

use bmwqemu;
use autotest;

use Mojo::File 'path';
use Try::Tiny;

# a run is comprised of these individual resources
has [qw(casedir needles_dir productdir)] => undef;

sub new ($class, %args) {
    my $self = $class->SUPER::new(
        casedir => undef,
        needles_dir => undef,
        productdir => path($args{productdir}),
    );
    $bmwqemu::vars{PRODUCTDIR} = $self->productdir->to_string;

    return $self;
}

sub prepare_casedir ($self, $casedir) {
    $self->{casedir} = checkout_git_repo_and_branch($casedir, 'CASEDIR');
    $bmwqemu::vars{CASEDIR} = $self->casedir->to_string;

    # as we are about to load the test modules checkout the specified git refspec,
    # if specified, or simply store the git hash that has been used. If it is not a
    # git repo fail silently, i.e. store an empty variable
    $bmwqemu::vars{TEST_GIT_HASH} = checkout_git_refspec($casedir => 'TEST_GIT_REFSPEC');
}

sub prepare_needles ($self, $needles_dir) {
    $self->needles_dir(checkout_git_repo_and_branch($needles_dir, 'NEEDLES_DIR'));
    $bmwqemu::vars{NEEDLES_DIR} = $self->needles_dir->to_string if $self->needles_dir;
}

=head2 load_test_schedule

Loads the test schedule (main.pm) or particular test modules if the `SCHEDULE` variable is present.

=cut

sub load_test_schedule ($self, $schedule = undef) {
    # add lib of the test distributions - but only for main.pm not to pollute
    # further dependencies (the tests get it through autotest)
    my @oldINC = @INC;
    unshift @INC, $self->casedir->child('/lib')->to_string;
    if ($schedule) {
        unshift @INC, '.' unless $self->casedir->is_abs;
        bmwqemu::fctinfo 'Enforced test schedule by \'SCHEDULE\' variable in action';
        $bmwqemu::vars{INCLUDE_MODULES} = undef;
        autotest::loadtest($_ =~ qr/\./ ? $_ : $_ . '.pm') foreach split(/[, ]+/, $schedule);
        $bmwqemu::vars{INCLUDE_MODULES} = 'none';
    }
    my $main_path = $self->productdir->child('main.pm');
    try {
        if (-e $main_path) {
            unshift @INC, '.';
            require $main_path;
        }
        elsif (!$self->productdir->is_abs && -e $self->casedir->child($main_path)) {
            require($self->casedir->child($main_path)->to_string);
        }
        elsif ($self->productdir && !-e $self->productdir) {
            die 'PRODUCTDIR ' . $self->productdir . ' invalid, could not be found';
        }
        elsif (!$schedule) {
            die "'SCHEDULE' not set and $main_path not found, need one of both";
        }
    }
    catch {
        # record that the exception is caused by the tests themselves before letting it pass
        my $error_message = $_;
        bmwqemu::serialize_state(component => 'tests', msg => 'unable to load main.pm, check the log for the cause (e.g. syntax error)');
        die "$error_message\n";
    };
    @INC = @oldINC;
}

1;
