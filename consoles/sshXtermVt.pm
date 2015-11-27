package consoles::sshXtermVt;
use base 'consoles::ssh';
use strict;
use warnings;
use testapi qw/get_var/;
require IPC::System::Simple;
use autodie qw(:system);

sub init() {
    my ($self) = @_;
    $self->{name} = 'ssh-xterm_vt';
}

sub activate() {
    my ($self, $testapi_console, $console_args) = @_;

    my $sshcommand = $self->sshCommand(get_var("PARMFILE")->{Hostname});
    my $worker     = $self->{backend}->{consoles}->{worker};
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
    sleep 2;
    $worker->type_string({text => $testapi::password . "\n"});
}

1;
