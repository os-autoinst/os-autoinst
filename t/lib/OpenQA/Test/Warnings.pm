# Copyright (C) 2020 SUSE LLC
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

=head1 NAME

OpenQA::Test::Warnings - Test::Warnings Wrapper for Test::Output functions

=cut

package OpenQA::Test::Warnings;
use strict;
use warnings;

use Test::Output ();
use Test::More   ();
use Test::Warnings 'warnings';

use base 'Exporter';
our @EXPORT_OK = qw(&stderr_like &stderr_unlike &combined_like);

sub stderr_like(&$;$) {
    my ($code, $re, $label) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 3;
    my @warnings = warnings(sub {
            Test::Output::stderr_like(sub { $code->() }, $re, $label);
    });
    _check_warnings(stderr_like => @warnings);
}

sub stderr_unlike(&$;$) {
    my ($code, $re, $label) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 3;
    my @warnings = warnings(sub {
            Test::Output::stderr_unlike(sub { $code->() }, $re, $label);
    });
    _check_warnings(stderr_unlike => @warnings);
}

sub combined_like(&$;$) {
    my ($code, $re, $label) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 3;
    my @warnings = warnings(sub {
            Test::Output::combined_like(sub { $code->() }, $re, $label);
    });
    _check_warnings(combined_like => @warnings);
}

sub _check_warnings {
    my ($func, @warnings) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    if (@warnings) {
        Test::More::is(scalar @warnings, 0, "Got no unexpected warnings in $func() call")
          or Test::More::diag "Warnings: " . join '', @warnings;
    }
}

=head2 FUNCTIONS

=over

=item stderr_like, stderr_unlike, combined_like

These functions are wrappers for the corresponding L<Test::Output> functions,
but they are wrapped with a call to C<Test::Warnings::warnings()>, and they
check if there were no additional warnings.

Because Test::Output captures the output, unexpected warnings are not seen in
the test output, and Test::Warnings will just report that there were warnings,
but not the content.

There is a proposal for L<Test::Warnings> that would make this module obsolete,
but not sure yet if it will get accepted:
L<https://github.com/karenetheridge/Test-Warnings/pull/10>

=back

=cut

1;
