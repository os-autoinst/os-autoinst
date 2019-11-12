# SPDX-Identifier: CC0-1.0
#
use 5.018;
use strict;
use warnings;

use base 'basetest';

use testapi;

sub run {
    select_console 'brokenssh';
}

1;
