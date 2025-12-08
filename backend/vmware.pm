# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -strict, -signatures;
use Object::Pad;

class backend::vmware : isa(backend::virt_ssh);

1;
