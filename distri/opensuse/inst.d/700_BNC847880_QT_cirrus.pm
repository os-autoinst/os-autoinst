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
    sendautotype('echo "export QT_GRAPHICSSYSTEM=native" >> /etc/profile.d/desktop-data.sh\n');
    sendautotype("exit\n");
    waitforneedle("BNC847880-xterm", 5);
}

1;
