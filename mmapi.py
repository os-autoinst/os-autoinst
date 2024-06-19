# publish all mm API methods over perl into the modules context.
# Use with `import mmapi; mmapi.method()` or `from mmapi import *`
import perl

perl.use("mmapi")
for i in dir(perl.mmapi):
    locals()[i] = getattr(perl.mmapi, i)
