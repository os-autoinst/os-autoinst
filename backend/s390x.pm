#!/usr/bin/perl -w
package backend::s390x;
use strict;
use base ('backend::baseclass');

sub init($) {
    # nothing to do for now.
}

sub do_start_vm($) {
    my $self = shift;
}

1;
