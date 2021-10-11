# Copyright 2017 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

=head2 OpenQA::Test::RunArgs

Object passed to loadtest as an optional parameter. Tests wishing to use
context with loadtest should create a subclass of this object.

=cut

package OpenQA::Test::RunArgs;
use Mojo::Base -base, -signatures;

1;
