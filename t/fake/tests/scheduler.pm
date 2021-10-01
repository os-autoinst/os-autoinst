use Mojo::Base -strict, -signatures;
use base 'basetest';
use autotest 'loadtest';

sub run {
    loadtest 'tests/next.pm';
}
1;
