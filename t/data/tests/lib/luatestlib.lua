-- example test library to be imported by lua test modules

local modname = "luatestlib"
local M = {}
_G[modname] = M
package.loaded[modname] = M

function M.testfunc3()
    print("testfunc3")
    return 44
end
