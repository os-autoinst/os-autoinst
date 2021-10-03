# Copyright 2019-2021 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# publish all test API methods over perl into the modules context.
# Use with `import testapi; testapi.method()` or `from testapi import *`
import perl

perl.use("testapi")
for i in dir(perl.testapi):
    locals()[i] = getattr(perl.testapi, i)
