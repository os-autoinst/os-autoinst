#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Test::Pod;
use File::Basename;
my $curdir = dirname(__FILE__);

my @files = ($curdir . '/../testapi.pm');
all_pod_files_ok(@files);
