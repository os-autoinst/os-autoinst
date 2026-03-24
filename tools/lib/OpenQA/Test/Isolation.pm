package OpenQA::Test::Isolation;

use Mojo::Base -strict, -signatures;
use Mojo::File qw(tempdir);
use Mojo::Util qw(scope_guard);
use FindBin;
use Cwd qw(getcwd);

use Exporter 'import';
our @EXPORT_OK = qw(setup_isolated_workdir);

sub setup_isolated_workdir () {
    my $original_cwd = getcwd();
    my $dir = tempdir("/tmp/$FindBin::Script-XXXX");
    chdir $dir;
    return scope_guard sub {
        chdir $original_cwd;
        undef $dir;
    };
}

1;
