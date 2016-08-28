#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Pod;

my @files = qw{../testapi.pm};
all_pod_files_ok(@files);
