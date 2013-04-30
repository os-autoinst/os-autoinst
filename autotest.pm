package autotest;
use bmwqemu;

sub runtest
{
	my($script,$testfunc)=@_;
	my $name=$script;
	$name=~s{.*/}{}; $name=~s{^\d+_}{}; $name=~s/\.pm$//;
	{
		eval "package $name;
		require \$script;" or (diag("error on $script: $@") and return);
	}
	my $test=$name->new();
	return unless $test->is_applicable;
	if (defined $testfunc) {
		my $ret;
		unless(defined $ENV{'checklog_working'} && $ENV{'checklog_working'}) {
			if(open(my $fd, ">currentstep")) { # to track progress
				print $fd "$script\n$name\n";
				close $fd;
			}
			modstart "starting $name $script";
			$ret=&$testfunc($test);
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
}

sub runtestdir($&)
{ my($dir,$testfunc)=@_;
	foreach my $script (<$dir/*.pm>) {
		runtest($script,$testfunc);
	}
}

1;
