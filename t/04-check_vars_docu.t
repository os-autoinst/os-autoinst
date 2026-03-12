#!/usr/bin/perl
#
# Copyright 2015 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later


use Test::Most;
use Mojo::Base -strict, -signatures;

use Test::Warnings ':report_warnings';
use Feature::Compat::Try;
use FindBin;
use File::Find;
use Mojo::File qw(path tempdir);
use Mojo::Util qw(scope_guard);
require IPC::System::Simple;
use autodie ':all';

use constant {
    BACKEND_DIR => "$FindBin::Bin/../backend",
    DOC_DIR => "$FindBin::Bin/../doc",
};
use constant VARS_DOC => DOC_DIR . '/backend_vars.md';

my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
my $cleanup_dir = scope_guard sub { chdir $FindBin::Bin; undef $dir };
chdir $dir;

# array of ignored "backends"
my @backend_blocklist = qw();
# blocklist of vars per backend. These vars will be ignored during vars exploration
my %var_blocklist = (
    QEMU => ['WORKER_ID', 'WORKER_INSTANCE', 'NAME'],
    VAGRANT => ['QEMUCPUS', 'QEMURAM'],
    GENERALHW => ['HDD_1'],
    SVIRT => ['JOBTOKEN'],
);
# in case we want to present backend under different name, place it here
my %backend_renames = (BASECLASS => 'Common', IKVM => 'IPMI');

my %documented_vars = ();
my %found_vars;
my $error_found = 0;
# ignore errors for now
my $ignore_errors = 1;


sub read_doc () {
    # read and parse old vars doc
    my @lines = split /\n/, path(VARS_DOC)->slurp;
    my $backend;
    for my $line (@lines) {
        if ($line =~ /^## ([^ ]+) backend$/) {
            $backend = $1;
        }
        elsif ($backend && $line =~ /^\| (.*) \| (.*) \| (.*) \| (.*) \|$/) {
            my ($var, $value, $default, $explanation) = ($1, $2, $3, $4);
            $var =~ s/^\s+|\s+$//g;
            $value =~ s/^\s+|\s+$//g;
            $default =~ s/^\s+|\s+$//g;
            $explanation =~ s/^\s+|\s+$//g;
            next if $var eq 'Variable' or $var =~ /^[ \-]*-*[ \-]*$/;
            # Unescape pipes in explanation
            $explanation =~ s/\\\|/|/g;
            $documented_vars{$backend}{$var} = [$value, $default, $explanation];
        }
    }
}

sub write_doc () {
    my $data = <<EO_HEADER;
Supported variables per backend
===============================

EO_HEADER
    for my $backend (sort keys %found_vars) {
        my $backend = uc $backend;
        $data .= "## $backend backend\n\n";
        $data .= "| Variable | Values allowed | Default value | Explanation |\n";
        $data .= "| --- | --- | --- | --- |\n";
        for my $var (sort keys %{$found_vars{$backend}}) {
            # skip perl variables i.e. $bmwqemu{$k}
            next if ($var =~ /^\$[a-zA-Z]/);
            next if (grep { /$var/ } @{$var_blocklist{$backend}});
            unless ($documented_vars{$backend}{$var}) {
                $error_found = 1;    # uncoverable statement
                $documented_vars{$backend}{$var} = ['', '', ''];    # uncoverable statement
                fail "missing documentation for backend $backend variable $var, please update backend_vars";    # uncoverable statement
            }
            my @var_docu = @{$documented_vars{$backend}{$var}};
            # Escape pipes for Markdown
            @var_docu = map { defined $_ ? $_ : '' } @var_docu;
            @var_docu = map { s/\|/\\\|/g; $_ } @var_docu;
            $data .= sprintf "| %s | %s | %s | %s |\n", $var, @var_docu;
        }
        $data .= "\n";
    }
    path(VARS_DOC . '.newvars')->spew($data);
}

sub read_backend_pm {    # no:style:signatures
    my ($backend) = $_ =~ /^([^\.]+)\.pm/;
    return unless $backend;
    # uncoverable statement count:2
    return if (grep { /$backend/i } @backend_blocklist);
    $backend = uc $backend;
    $backend = uc $backend_renames{$backend} if $backend_renames{$backend};
    my @lines = split /\n/, path($File::Find::name)->slurp;
    for my $line (@lines) {
        my @vars = $line =~ /(?:\$bmwqemu::|\$)vars(?:->)?{["']?([^}"']+)["']?}/g;
        for my $var (@vars) {
            # initially I used array and kept greping through to maintain uniqueness, but I had problem greping ISO_$i
            # and HDD_$i variables. And hash is faster anyway, memory consumption is no issue here.
            $found_vars{$backend}{$var} = 1;
        }
    }
}

read_doc;
# for each backend file vars usage
find(\&read_backend_pm, (BACKEND_DIR));
# check if vars are properly documented and update data
write_doc;
path(VARS_DOC . '.newvars')->remove;
$error_found = $ignore_errors ? 0 : $error_found;
ok($error_found ? 0 : 1, 'No errors found');
done_testing;
