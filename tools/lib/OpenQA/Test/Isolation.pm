package OpenQA::Test::Isolation;

use Mojo::Base -strict, -signatures;
use Mojo::Util qw(scope_guard);
use FindBin;
use Cwd qw(getcwd);
use File::Temp ();
use File::Path ();
use Mojo::File qw(path);

use Exporter 'import';
our @EXPORT_OK = qw(setup_isolated_workdir);

sub setup_isolated_workdir ($workdir = undef) {
    my $original_cwd = getcwd();
    my $owner_pid = $$;
    my $retain = defined $workdir;
    my $dir = $retain
      ? path($workdir)->to_abs->make_path
      : path(File::Temp::tempdir("$FindBin::Script-XXXX", TMPDIR => 1, CLEANUP => 0));
    chdir $dir;
    my $guard = scope_guard sub {
        # only cleanup in the process that created the directory to avoid
        # children removing the directory on exit
        return if $$ != $owner_pid;
        chdir $original_cwd;
        return if $retain || !-d $dir;
        # errors are collected rather than raised so a workdir which cannot be
        # removed completely is kept for inspection instead of failing the run
        File::Path::remove_tree($dir, {error => \my $errors});
    };
    return wantarray ? ($guard, $dir) : $guard;    ## no critic (Community::Wantarray)
}

1;
