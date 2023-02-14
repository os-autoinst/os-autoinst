#!/usr/bin/perl
# Copyright 2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Test::Most;

use FindBin '$Bin';
chdir "$Bin/..";

ok system(qq{git grep -I -l 'Copyright \((C)\|(c)\|©\)' ':!COPYING' ':!external/'}) != 0, 'No redundant copyright character';
ok system(qq{git grep -I -l 'This program is free software.*if not, see <http://www.gnu.org/licenses/' ':!COPYING' ':!external/' ':!xt/01-style.t'}) != 0, 'No verbatim licenses in source files';
ok system(qq{git grep -I -l '[#/ ]*SPDX-License-Identifier ' ':!COPYING' ':!external/' ':!xt/01-style.t'}) != 0, 'SPDX-License-Identifier correctly terminated';
is qx{git grep -I -L '^use Test::Most' t/**.t}, '', 'All tests use Test::Most';
is qx{git grep -I -L '^use Test::Warnings' t/**.t}, '', 'All tests use Test::Warnings';
is qx{git grep -I -l '^use testapi' backend/ consoles/}, '', 'No backend or console files use external facing testapi';
is qx{git grep -l -e '^sub \\S\\+ [^(]\\+' --and --not -e 'sub [(\{]' --and --not -e 'sub \\S\\+(' --and --not -e 'sub \\S\\+;' --and --not -e '# no:style:signatures' ':!external/'}, '', 'All files use sub signatures everywhere (nameless and in-place definitions still allowed)';
is qx{git grep -L '^#!.*perl' t/**.t}, '', 'All test files have shebang';
is qx{git ls-files -s t/**.t | grep -v ^1007}, '', 'All test modules are executable';
is qx{git grep -l '^use POSIX;'}, '', 'Use of bare POSIX import is discouraged, see https://perldoc.perl.org/POSIX';
is qx{git grep --all-match -P -e '^use Mojo::Base' -e '^use base (?!.*# no:style)'}, '', 'No redundant Mojo::Base+base';
is qx{git grep -I -l -P '^use (warnings|strict)' ':!external/'}, '', 'No files using "warning|strict", should use Mojo::Base instead';
is qx{git grep -I -l 'sub [a-z_A-Z0-9]\\+()'}, '', 'Consistent space before function signatures (this is not ensured by perltidy)';
done_testing;
