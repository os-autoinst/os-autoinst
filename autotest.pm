package autotest;
use strict;
use bmwqemu;
use needle;
use JSON;

our %tests;     # scheduled or run tests
our @testorder; # for keeping them in order
our $running;   # currently running test or undef

# all so ugly ...
$SIG{ALRM} = sub {
	if ($running) {
		$running->fail_if_running();
		$running = undef;
	}
	save_results();
	stop_vm();
	die "die due to SIGALARM\n";
};

sub runtest
{
	my($script,$testfunc)=@_;
	return unless $script =~ /.*\/(\w+)\.d\/\d+_(.+)\.pm$/;
	my $category=$1;
	my $name=$2;
	my $test;
	if (exists $tests{$name}) {
		$test = $tests{$name};
		return unless $test->is_applicable;
	} else {
		eval "package $name; require \$script;";
		if ($@) {
			my $msg = "error on $script: $@";
			diag($msg);
			die $msg;
		}
		$test=$name->new($category);
		$tests{$name} = $test;

		return unless $test->is_applicable;
		push @testorder, $test;
	}
	if (defined $testfunc) {
		my $ret;
		unless(defined $ENV{'checklog_working'} && $ENV{'checklog_working'}) {
			modstart "starting $name $script";
			$running = $test;
			$test->start();
			save_results();
			bmwqemu::set_current_test($test);
			eval {
				$ret=&$testfunc($test);
			};
			if ($@) {
				warn "test $name died: $@\n";
				$test->fail_if_running();
				$running = undef;
				save_results();
				stop_vm();
				die "test $name died: $@\n";
			}
			$test->done();
			bmwqemu::set_current_test(undef);
			save_results();
			#sleep 1;
			diag "||| finished $name";
		}
		else {
			modstart "checking $name $script";
			$ret=&$testfunc($test);
			diag "";
		}

		return $ret;
	}
	else {
		diag "scheduling $name $script";
	}
}

sub runtestlist($&)
{
	my($tests,$testfunc)=@_;
	foreach my $script (@$tests) {
		runtest($script,$testfunc);
	}
	$running = undef;
}

sub runtestdir($&)
{ my($dir,$testfunc)=@_;
	foreach my $script (<$dir/*.pm>) {
		runtest($script,$testfunc);
	}
	$running = undef;
}

sub results()
{
	my $results = [];
	for my $t (@testorder) {
		push @$results, $t->json();
	}
	return $results;
}

# dump all info in one big file. Alternatively each test could write
# one file and we collect only the overall status.
sub save_results()
{
	my $fn = shift || result_dir()."/results.json";
	open(my $fd, ">", $fn) or die "can not write results";
	print $fd to_json({
		'needledir' => needle::get_needle_dir(),
		'running' => $running?ref($running):'',
		'testmodules' => results()
		}, { pretty => 1 });
	close($fd);
}

1;
