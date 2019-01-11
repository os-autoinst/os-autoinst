#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Fatal;
use Test::Warnings;

BEGIN {
    unshift @INC, '..';
}

# This test merely shows how perl objects and modules can be accessed from
# python

# import all test API methods into global scope of python test modules so that
# we do not need to write any prefix on each call like "perl.get_var"
use testapi;
use Inline Python => "for i in dir(perl): globals()[i] = getattr(perl, i)";

use Inline 'Python';
done_testing;
__END__
__Python__
print(get_var('FOO', 'foo'))
