from testapi import *

def run(self): # it's not supported
    diag("run_args are not supported in python.")
    set_var("PY_SUPPORT_FN_NOT_CALLED", lorem())

def lorem():
    return "sit amet"
