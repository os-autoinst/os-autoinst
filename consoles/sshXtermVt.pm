package consoles::sshXtermVt;
use base 'consoles::ssh';
use strict;
use warnings;
use testapi qw/get_var/;
require IPC::System::Simple;
use autodie qw(:all);

sub init() {
    my ($self) = @_;
    $self->{name} = 'ssh-xterm_vt';
}

sub activate {
    my ($self) = @_;

    my $testapi_console = $self->{testapi_console};
    my $ssh_args = $self->{args};

    my $hostname = $ssh_args->{host} || get_var("PARMFILE")->{Hostname};
    my $password = $ssh_args->{password} || $testapi::password;
    my $sshcommand = $self->sshCommand($hostname);
    my $display    = $self->display;

    $sshcommand = "TERM=xterm " . $sshcommand;
    my $xterm_vt_cmd = "xterm-console";
    my $window_name  = "ssh:$testapi_console";
    eval { system("DISPLAY=$display $xterm_vt_cmd -title $window_name -e bash -c '$sshcommand' & echo \$!") };
    if (my $E = $@) {
        die "cant' start xterm on $display (err: $! retval: $?)";
    }
    my $window_id = qx"DISPLAY=$display xdotool search --sync --limit 1 $window_name";
    chomp($window_id);

    $self->{window_id} = $window_id;

    # FIXME: assert_screen('xterm_password');
    sleep 3;
    #my $worker = $self->backend->console('worker');
    $self->backend->type_string({text => $password . "\n"});
}

1;
