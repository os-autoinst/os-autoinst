#!/usr/bin/perl
# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later
use Test::Most;
use Test::Warnings qw(:report_warnings);
use Test::Output qw(combined_like);
use FindBin '$Bin';
use YAML::PP qw(Load);
use Syntax::Keyword::Try;

my $script = "$Bin/../script/os-autoinst-testmodules-strict";
require $script;

subtest 'various inputs' => sub {
    my $data = do { local $/; <DATA> };
    my @tests = Load $data;
    for my $i (0 .. $#tests) {
        note "################################### $i";
        my $test = $tests[$i];
        my ($in, $exp) = @$test;
        note $in;
        my $doc = PPI::Document->new(\$in) or die "Could not parse code";
        my $module;
        my $err;
        try {
            $module = main::analyze($doc);
        }
        catch ($e) {
            $err = $e;
        }
        if ($in =~ m/## no os-autoinst style/) {
            ok $module->{nofix};
            next;
        }
        if ($exp) {
            my $changed = fix($module);
            if ($changed) {
                $changed =~ s/^\n+//;
            }
            $exp =~ s/^\n+//;
            is $changed, $exp;
        }
        else {
            like $err, qr{No base};
        }
    }
};

subtest 'main' => sub {
    my @args = qw(t/data/tests/bar/module2.pm);
    combined_like { main::main({}, @args) } qr/Would change @args/, 'checking file';

    my $code = 'use CGI';
    combined_like { main::main({}, \$code) } qr/Error.*No base/, 'no base statements';

    $code = 'use base "x"';
    combined_like { main::main({}, \$code) } qr/Would change/, 'checking string';

    $code = 'use base "x"';
    combined_like { main::main({write => 1}, \$code) } qr/Writing/, 'changing string';
    is $code, q{use Mojo::Base 'x', -signatures;}, 'changed string like expected';
};

subtest 'script' => sub {
    my $out = qx{$^X $script};
    is $? >> 8, 1, 'script exits with 1 in case of usage errors';

    $out = qx{$^X $script t/data/tests/bar/module2.pm};
    is $? >> 8, 2, 'script exits with 2 in case of changes';
};

done_testing;

__DATA__
---
- |
    use Mojo::Base -strict;
    use base 'basetest';

    sub run { }
- |
    use Mojo::Base 'basetest', -signatures;

    sub run { }

---
- |
    use Mojo::Base -strict;

- |

---
- |
    # comment
    use base 'basetest';

    sub run { }
- |
    # comment
    use Mojo::Base 'basetest', -signatures;

    sub run { }

---
- |
    use Mojo::Base 'basetest', -signatures;

- |
    use Mojo::Base 'basetest', -signatures;


---
- |
    use Mojo::Base 'basetest', -strict;
    use base 'opensusebasetest';

- |
    use Mojo::Base qw(basetest opensusebasetest), -signatures;


---
- |
    use Mojo::Base 'basetest', -strict;
    use base 'basetest';

- |
    use Mojo::Base 'basetest', -signatures;


---
- |
    sub run { }
- |

---
- |
    use base qw(foo bar);

- |
    use Mojo::Base qw(foo bar), -signatures;


---
- |
    use base 'foo', 'bar';

- |
    use Mojo::Base qw(foo bar), -signatures;


---
- |
    use Mojo::Base qw(basetest basetest2), -strict;
    use base 'basetest3';

- |
    use Mojo::Base qw(basetest basetest2 basetest3), -signatures;


---
- |
    use base 'basetest1';
    use base 'basetest2';

- |
    use Mojo::Base qw(basetest1 basetest2), -signatures;


---
- |
    use parent 'basetest1';
    use base 'basetest2';

- |
    use Mojo::Base qw(basetest1 basetest2), -signatures;


---
- |
    # These are barewords, but we also handle them
    use parent basetest1;
    use base basetest2;

- |
    # These are barewords, but we also handle them
    use Mojo::Base qw(basetest1 basetest2), -signatures;

---
- |
    ## no os-autoinst style
    use base 'basetest';

- |
    ## no os-autoinst style
    use base 'basetest';
