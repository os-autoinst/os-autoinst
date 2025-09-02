# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

use Object::Pad;

# new baseclass that can be used in backend::hyperv.
# TODO:
# 1. move all necessary joint svirt+hyperv+vmware relevant implementation here
# 2. make hyperv and svirt inherit from here
# 3. make use of hyperv backend directly
# 4. deprecate using svirt(hyperv)
# 5. move more hyperv functionality from osado to backend
# 6. repeat the same steps for vmware
# 7. make svirt inherit "roles" hyperv+vmware
# 8. potentially remove virt_ssh baseclass again if hyperv+vmware backends
#    implement all in roles
class backend::virt_ssh : isa(backend::virt);

1;
