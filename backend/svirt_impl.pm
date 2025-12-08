# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;
use Object::Pad;

class backend::svirt_impl : isa(backend::virt_ssh);

1;
