from testapi import *


def run():  # missing self, raises TypeError
    diag("this doesn't run, bad run definition")
    set_var("PY_SUPPORT_FN_NOT_CALLED", lorem())


def lorem():
    return "sit amet"
