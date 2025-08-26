# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Mojo::Base -base, -signatures;
use Object::Pad;

class backend::hyperv : isa(backend::svirt);


1;
