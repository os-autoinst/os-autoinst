 elsif ($backend_console eq "remote-vnc") {
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
        $console_info->{console} = $self->{vnc};
        $console_info->{vnc}     = $self->{vnc};
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
            $console_info->{vncviewer_pid} = $vncviewer_pid;
            #CORE::say __FILE__ .':'. __LINE__ .':'.(caller 0)[3].':'.bmwqemu::pp($console_info);
        }
    }
 sub disable() {
    elsif ($backend_console eq "remote-vnc") {
        #CORE::say __FILE__ .':'. __LINE__ .':'.(caller 0)[3].':'.bmwqemu::pp($console_info);
        if (exists $console_info->{vncviewer_pid}) {
            kill 'KILL', $console_info->{vncviewer_pid};
        }
        # FIXME? close remote socket?
        $console_info->{console} = undef;
        # FIXME: only do when {vnc} currently is "remote-vnc" (not local-Xvnc)?
        $self->{vnc} = undef;
    }
}
 
 # override
sub select() {}
