use base "installstep";
use bmwqemu;

# Only because of kde/qt has a rendering error on i586 in qemu (bnc#847880).
# Remove after QT fixed the bug

sub is_applicable()
{
    return 1 if $ENV{DESKTOP} eq "kde";
}

sub run()
{
    my $self=shift;
    x11_start_program("xterm");
    become_root();
    sendautotype('echo "QT_GRAPHICSSYSTEM=native" >> /etc/environment\n');
    $self->take_screenshot();
    sendautotype("exit\n");
}

1;
