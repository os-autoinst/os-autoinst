use Mojo::Base -strict, -signatures;
use base 'basetest';

sub run { }

sub test_flags {
    return {ignore_failure => 1, fatal => 0};
}

1;
