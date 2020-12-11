#!/usr/bin/perl

use Test::Most;

use Test::Pod;
use File::Basename;
my $curdir = dirname(__FILE__);

my @files = ($curdir . '/../testapi.pm');
all_pod_files_ok(@files);
