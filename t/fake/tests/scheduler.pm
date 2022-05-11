use Mojo::Base 'basetest', -signatures;
use autotest 'loadtest';

sub run ($) {
    loadtest 'tests/next.pm';
}
1;
