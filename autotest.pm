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
	&$testfunc($test);
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
