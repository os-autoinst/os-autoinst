use Mojo::Base -strict;
use base 'basetest';
use autotest 'loadtest';

sub run {
    loadtest 'tests/next.pm';
}
1;
