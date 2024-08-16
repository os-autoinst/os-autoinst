#!/usr/bin/perl

use Test::Most;
use Test::Exception;
use Test::Warnings;
use Mojo::Base -strict, -signatures;

BEGIN {
    unshift @INC, '..';
}

plan skip_all => 'Inline::Python is not available' unless eval { require Inline::Python };

# This test merely shows how perl objects and modules can be accessed from
# python

# import all test API methods into global scope of python test modules so that
# we do not need to write any prefix on each call like "perl.get_var"
use testapi;
Inline::Python::py_eval('for i in dir(perl): globals()[i] = getattr(perl, i)');

my $python_code = <<~'EOM';
print(get_var('FOO', 'foo'))
set_var('MY_PYTHON_VARIABLE', 42)
assert get_required_var('MY_PYTHON_VARIABLE') == 42, "Could not find get_var/set_var variable"
EOM

lives_ok { Inline::Python::py_eval($python_code) } 'simple use of test API does not crash';
done_testing;
