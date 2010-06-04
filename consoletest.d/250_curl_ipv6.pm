package curl_ipv6;
use base "basetest";
use bmwqemu;
# test for bug https://bugzilla.novell.com/show_bug.cgi?id=598574
sub run()
{
	script_run('curl www3.zq1.de/test.txt');
	sleep 2;
	script_run('rpm -q curl libcurl4');
	sleep 2;
}

1;
