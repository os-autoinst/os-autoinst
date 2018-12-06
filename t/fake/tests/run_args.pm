use 5.018;
use strict;
use warnings;

use base 'basetest';

sub run {
    my ($self, $rargs) = @_;

    unless (defined $rargs) {
        die 'run_args not passed through';
    }
}
1;
