package autotest;
use strict;
use bmwqemu;
use JSON;

our %tests;     # scheduled or run tests
our @testorder; # for keeping them in order
our $running;   # currently running test or undef

sub runtest
{
	my($script,$testfunc)=@_;
	my $name=$script;
	my $test;
	$name=~s{.*/}{}; $name=~s{^\d+_}{}; $name=~s/\.pm$//;
	if (exists $tests{$name}) {
		$test = $tests{$name};
	} else {
		{
			eval "package $name;
			require \$script;" or (diag("error on $script: $@") and return);
		}
		$test=$name->new();
		push @testorder, $test;
		$tests{$name} = $test;
	}
	return unless $test->is_applicable;
	if (defined $testfunc) {
		my $ret;
		unless(defined $ENV{'checklog_working'} && $ENV{'checklog_working'}) {
			modstart "starting $name $script";
			$running = $test;
			$test->start();
			save_results();
			eval {
				$ret=&$testfunc($test);
			};
			if ($@) {
				$test->fail_if_running();
				$running = undef;
				save_results();
				stop_vm();
				die "test $name died: $@\n";
			}
			$test->done();
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
		push @$results, {
			'name' => ref $t,
			'details' => $t->details(),
			'result' => $t->result(),
		};
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
		'running' => $running?ref($running):'',
		'testmodules' => results()
		}, { pretty => 1 });
	close($fd);
}

1;
