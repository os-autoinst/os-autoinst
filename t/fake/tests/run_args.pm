use 5.018;
use Mojo::Base -strict, -signatures;

use base 'basetest';

sub run ($self, $rargs) {

    unless (defined $rargs) {
        die 'run_args not passed through';
    }
}
1;
