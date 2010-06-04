package autotest;

sub runtestdir($&)
{ my($dir,$testfunc)=@_;
	foreach my $script (<$dir/*.pm>) {
		my $name=$script;
		$name=~s{.*/\d+_}{}; $name=~s/\.pm$//;
		require $script;
		my $test=$name->new();
		next unless $test->is_applicable;
		&$testfunc($test);
	}
}

1;
