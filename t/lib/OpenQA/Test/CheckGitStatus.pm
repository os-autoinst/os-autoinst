package OpenQA::Test::CheckGitStatus;
use Mojo::Base -strict, -signatures;
my $CHECK_GIT_STATUS = $ENV{CHECK_GIT_STATUS};
# prevent subsequent perl processes to check the status
$ENV{CHECK_GIT_STATUS} = 0;

my $cwd;
# Get the PID when loading the module to check later
my $pid = $$;

if ($CHECK_GIT_STATUS) {
    require Test::More;
    require File::Which;
    require Cwd;
    $cwd = Cwd::cwd();
}

sub check_status () {
    my @lines;
    {
        local $?;
        chdir $cwd;
        my $git = File::Which::which('git');
        return unless $git;
        my $cmd = 'git rev-parse --git-dir';
        my $out = qx{$cmd};
        return if $? != 0;
        $cmd = 'git status --porcelain=v1 2>&1';
        @lines = qx{$cmd};
        die "Problem running git:\n" . join '', @lines if $? != 0;
    }
    if (@lines > 0) {
        Test::More::diag("Error: modified or untracked files\n" . join '', @lines);
        $? = 1;
    }
}

END {
    # Check $pid - don't run this in forked processes
    check_status() if $$ == $pid and $CHECK_GIT_STATUS;
}

1;
