use strict;
use warnings;

sub activate() {
    my ($self, $testapi_console, $console_args) = @_;

    my $hostname = get_var("PARMFILE")->{Hostname};
    my $password = get_var("DISPLAY")->{PASSWORD};
    $self->{vnc} = undef;    # REFACTOR see below
    $self->connect_vnc(
        {
            hostname => $hostname,
            port     => 5901,
            password => $password,
            ikvm     => 0,
        });
    if (exists get_var("DEBUG")->{vncviewer}) {

        # start vncviewer and remember it's pid so it can be killed at exit.
        my $subshell_pid;
        {
            defined($subshell_pid = fork) or die $!;
            $subshell_pid and last;
            # FIXME if the password could come from anyhwere, this
            # echo '$password' would be a bobby tables backdoor:
            exec "echo '$password' | vncviewer -autopass $hostname:1 & echo \$! >vncviewer_pid" or die "exec failed?";
        }
        waitpid $subshell_pid, 0;
        open my $fh, '<', 'vncviewer_pid' or die $!;
        my $vncviewer_pid = do { local $/; <$fh> };
        chomp($vncviewer_pid);
        $self->{vncviewer_pid} = $vncviewer_pid;
        #CORE::say __FILE__ .':'. __LINE__ .':'.(caller 0)[3].':'.bmwqemu::pp($console_info);
    }
}

sub disable() {
    my ($self) = @_;

    #CORE::say __FILE__ .':'. __LINE__ .':'.(caller 0)[3].':'.bmwqemu::pp($console_info);
    if (exists $self->{vncviewer_pid}) {
        kill 'KILL', $self->{vncviewer_pid};
    }
}

# override
sub select() {
}

1;
