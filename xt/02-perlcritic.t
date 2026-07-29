# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib/perlcritic";
use Test::Perl::Critic;
use Perl::Critic::Utils qw(all_perl_files);

my @files = grep { not m{^(?:t/fake|t/data|t/temp-.*|external/|install/|build/|local/|_Inline/|cover_db/|dist/)} } all_perl_files('.');
chomp(my @git_files = qx{git ls-files});
my %seen;
@files = grep { $seen{$_}++ } @files, @git_files if @git_files;    # exclude files not in Git
all_critic_ok(@files);
