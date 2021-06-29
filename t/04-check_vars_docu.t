#!/usr/bin/perl
#
# Copyright (c) 2015-2021 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.


use Test::Most;
use Mojo::Base -strict, -signatures;

use Test::Warnings ':report_warnings';
use FindBin;
use File::Find;
require IPC::System::Simple;
use autodie ':all';

use constant {
    BACKEND_DIR => "$FindBin::Bin/../backend",
    DOC_DIR     => "$FindBin::Bin/../doc",
};
use constant VARS_DOC => DOC_DIR . '/backend_vars.asciidoc';

# array of ignored "backends"
my @backend_blocklist = qw();
# blocklist of vars per backend. These vars will be ignored during vars exploration
my %var_blocklist = (QEMU => ['WORKER_ID', 'WORKER_INSTANCE']);
# in case we want to present backend under different name, place it here
my %backend_renames = (BASECLASS => 'Common', IKVM => 'IPMI');

my %documented_vars = ();
my %found_vars;
my $error_found = 0;
# ignore errors for now
my $ignore_errors = 1;

my $table_header = 'Variable;Values allowed;Default value;Explanation';

sub say ($text) {
    print STDERR "$text\n";
}

sub read_doc {
    # read and parse old vars doc
    my $docfh;
    open($docfh, '<', VARS_DOC);
    my $backend;
    my $reading;
    for my $line (<$docfh>) {
        if (!$backend && $line =~ /^\.([^ ]+) backend$/) {
            $backend = $1;
        }
        elsif ($backend) {
            if ($line =~ /^\|====/) {
                $reading = $reading ? 0 : 1;
                $backend = undef unless $reading;
            }
            elsif ($reading) {
                next if ($line =~ /$table_header/);
                my ($var, $value, $default, $explanation) = $line =~ /^([^;]+);\s*([^;]*);\s*([^;]*);\s*(.*)$/;
                next unless ($var);
                $default = '' unless (defined $default);
                $value   = '' unless (defined $value);
                unless ($explanation) {
                    fail "still missing explanation for backend $backend variable $var";
                }
                $documented_vars{$backend}{$var} = [$value, $default, $explanation];
            }
        }
    }
    close($docfh);
}

sub write_doc ($docfh) {
    open($docfh, '>', VARS_DOC . '.newvars');
    print $docfh <<EO_HEADER;
Supported variables per backend
-------------------------------

EO_HEADER
    for my $backend (sort keys %found_vars) {
        my $backend = uc $backend;
        print $docfh <<EO_BACKEND_HEADER;
.$backend backend
[grid="rows",format="csv"]
[options="header",cols="^m,^m,^m,v",separator=";"]
|====================
$table_header
EO_BACKEND_HEADER
        for my $var (sort keys %{$found_vars{$backend}}) {
            # skip perl variables i.e. $bmwqemu{$k}
            next if ($var =~ /^\$[a-zA-Z]/);
            next if (grep { /$var/ } @{$var_blocklist{$backend}});
            unless ($documented_vars{$backend}{$var}) {
                $error_found = 1;
                $documented_vars{$backend}{$var} = ['', '', ''];
                fail "missing documentation for backend $backend variable $var, please update backend_vars";
            }
            my @var_docu = @{$documented_vars{$backend}{$var}};
            printf $docfh "%s;%s;%s;%s\n", $var, @var_docu;
        }
        print $docfh <<EO_BACKEND_FOOTER;
|====================

EO_BACKEND_FOOTER
    }
}

sub read_backend_pm ($backend) {
    return if (grep { /$backend/i } @backend_blocklist);
    $backend = uc $backend;
    $backend = uc $backend_renames{$backend} if $backend_renames{$backend};
    my $fh;
    eval { open($fh, '<', $File::Find::name) };
    if (my $E = $@) {
        say 'Unable to open ' . $File::Find::name && return;
    }
    for my $line (<$fh>) {
        my @vars = $line =~ /(?:\$bmwqemu::|\$)vars(?:->)?{["']?([^}"']+)["']?}/g;
        for my $var (@vars) {
            # initially I used array and kept greping through to maintain uniqueness, but I had problem greping ISO_$i
            # and HDD_$i variables. And hash is faster anyway, memory consumption is no issue here.
            $found_vars{$backend}{$var} = 1;
        }
    }
    close($fh);
}

read_doc;
# for each backend file vars usage
find(\&read_backend_pm, (BACKEND_DIR));
# check if vars are properly documented and update data
write_doc;
$error_found = $ignore_errors ? 0 : $error_found;
ok($error_found ? 0 : 1, "No errors found");
done_testing;
