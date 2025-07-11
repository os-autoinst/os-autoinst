-- test module to be used loaded by unit tests in 08-autotest.t

use("testapi")
use("testlib")
use("testlib", {"testfunc2","@testarray","%testhash"})
use("testlib", {"testfunc37"}) -- this should raise a warning as it isn't exported
require 'luatestlib' -- load luatestlib.lua from ../lib/ dir

function run(self)
    assert(testfunc1() == 42)
    assert(testfunc2() == 43)
    assert(luatestlib.testfunc3() == 44)
    print("testarray:", table.concat(testarray,","))
    for k,v in pairs(testhash) do
        print(k.." = "..v)
    end
end
