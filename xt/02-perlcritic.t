# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;
use FindBin '$Bin';
use lib "$Bin/../external/os-autoinst-common/lib/perlcritic";
use Test::Perl::Critic;
use Perl::Critic::Utils qw(all_perl_files);

my @files = grep { not m{^(?:t/fake|t/data)} } all_perl_files('.');
all_critic_ok(@files);
