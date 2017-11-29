use 5.018;
use base 'basetest';

sub run {
    my ($self, $rargs) = @_;

    unless (defined $rargs) {
        die 'run_args not passed through';
    }
}
1;
