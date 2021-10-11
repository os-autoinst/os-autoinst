use Mojo::Base 'basetest', -signatures;

sub run ($) { }

sub test_flags ($) { {ignore_failure => 1, fatal => 0} }

1;
