use bmwqemu;
# test for bug https://bugzilla.novell.com/show_bug.cgi?id=598574
script_run('curl www3.zq1.de/test.txt');
sleep 2;

1;
