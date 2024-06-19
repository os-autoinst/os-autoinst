# publish all lock API methods over perl into the modules context.
# Use with `import lockapi; lockapi.method()` or `from lockapi import *`
import perl

perl.use("lockapi")
for i in dir(perl.testapi):
    locals()[i] = getattr(perl.lockapi, i)
