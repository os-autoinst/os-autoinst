package autotest;
use strict;
use bmwqemu;

our %tests;     # scheduled or run tests
our @testorder; # for keeping them in order
our $running;   # currently running test or undef

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
			bmwqemu::set_current_test($test);
			$test->start();
			bmwqemu::save_results(results());
			eval {
				$ret=&$testfunc($test);
			};
			if ($@) {
				warn "test $name died: $@\n";
				$test->fail_if_running();
				bmwqemu::set_current_test(undef);
				bmwqemu::save_results(results());
				stop_vm();
				die "test $name died: $@\n";
			}
			$test->done();
			bmwqemu::set_current_test(undef);
			bmwqemu::save_results(results());
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
	bmwqemu::set_current_test(undef);
}

sub runtestdir($&)
{ my($dir,$testfunc)=@_;
	foreach my $script (<$dir/*.pm>) {
		runtest($script,$testfunc);
	}
	bmwqemu::set_current_test(undef);
}

sub results()
{
	my $results = [];
	for my $t (@testorder) {
		push @$results, $t->json();
	}
	return $results;
}

1;
