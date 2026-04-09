package OpenQA::Test::Isolation;

use Mojo::Base -strict, -signatures;
use Mojo::File qw(tempdir);
use Mojo::Util qw(scope_guard);
use FindBin;
use Cwd qw(getcwd);
use File::Temp ();
use File::Path ();
use Mojo::File qw(path);

use Exporter 'import';
our @EXPORT_OK = qw(setup_isolated_workdir);

sub setup_isolated_workdir () {
    my $original_cwd = getcwd();
    my $owner_pid = $$;
    my $dir_str = File::Temp::tempdir("/tmp/$FindBin::Script-XXXX", CLEANUP => 0);
    my $dir = path($dir_str);
    chdir $dir_str;
    my $guard = scope_guard sub {
        # only cleanup in the process that created the directory to avoid
        # children removing the directory on exit
        return if $$ != $owner_pid;
        chdir $original_cwd;
        if (defined $dir_str && -d $dir_str) {
            File::Path::remove_tree($dir_str, {safe => 0});
        }
    };
    return wantarray ? ($guard, $dir) : $guard;
}

1;
