# Copyright 2018-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package OpenQA::Isotovideo::Interface;

use Mojo::Base -strict, -signatures;

# version of the test API and the API relevant to the worker
# -> increment on every change of such APIs
# -> never move that variable to another place (when refactoring)
#    because it may be accessed by the tests itself
our $version = 40;

# major version of the (web socket) API relevant to the developer mode
# -> increment when making non-backward compatible changes to that API
our $developer_mode_major_version = 1;
# minor version of the (web socket) API relevant to the developer mode
# -> reset to 0 when making non-backward compatible changes to that API
# -> increment when making backward compatible changes to that API
our $developer_mode_minor_version = 1;

1;
