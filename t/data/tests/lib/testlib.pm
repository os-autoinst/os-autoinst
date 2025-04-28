# example test library to be imported by test modules

package testlib;

use Mojo::Base 'Exporter', -signatures;

our @EXPORT = qw(testfunc1 @testarray %testhash);
our @EXPORT_OK = qw(testfunc2);

our @testarray = (1, 2, 3);
our %testhash = (foo => 'bar');

sub testfunc1 () {
    print("testfunc1\n");
    return 42;
}

sub testfunc2 () {
    print("testfunc2\n");
    return 43;
}


1;
