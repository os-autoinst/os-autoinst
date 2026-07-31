#!/usr/bin/perl

use Test::Most;
use Test::Pod;
use Mojo::File qw(path);

my $workspace = path(__FILE__)->dirname->sibling;

# Find all POD files and apply standard exclusion patterns
my @files = grep {
    my $f = path($_)->realpath->to_rel($workspace)->to_string;
    $f !~ m{^(?:t/fake|t/data|t/temp-.*|external/|install/|build/|local/|_Inline/|cover_db/|dist/)};
} all_pod_files('.');

# Scan each file to forbid empty POD headings (=headX with no text)
for my $file (@files) {
    if (path($file)->slurp =~ /^=head[1-4]\s*$/m) {
        die "Empty POD heading (=headX with no text) found in $file\n";    # uncoverable statement
    }
}

all_pod_files_ok(@files);
