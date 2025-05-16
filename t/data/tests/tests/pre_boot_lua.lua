use("testapi")
use("testlib")
use("testlib", {"testfunc2"})
require 'luatestlib' -- load luatestlib.lua from ../lib/ dir

function run(self)
    assert(testfunc1() == 42)
    assert(testfunc2() == 43)
    assert(luatestlib.testfunc3() == 44)
    -- just assume the first screen has a timeout so we should make sure not to miss it
    assert(not check_screen('nothing to match here', 0, 'no_wait', 1))
    send_key("esc")

    -- More sophisticated example call
    --assert_screen('on_prompt', 'timeout', get_var('TESTING_ASSERT_SCREEN_TIMEOUT') and 600 or 90)
end

--function test_flags(self)
--    return {fatal = 1}
--end

--function post_fail_hook(self)
--end
