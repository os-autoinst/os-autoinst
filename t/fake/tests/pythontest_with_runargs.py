from testapi import *

def run(*_):
    diag("run_args are not supported in python.")
    set_var("PY_SUPPORT_FN", lorem())

def lorem():
    return "ipsum"
