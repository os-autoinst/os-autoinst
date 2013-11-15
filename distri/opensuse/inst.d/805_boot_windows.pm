use base "installstep";
use bmwqemu;


sub is_applicable()
{
    return $ENV{DUALBOOT};
}

sub run()
{
    my $self = shift;

    # Eject the DVD
    sendkey "ctrl-alt-f3";
    sleep 4;
    sendkey "ctrl-alt-delete";

    # Bug in 13.1?
    qemusend "system_reset";

    # qemusend "eject ide1-cd0";

    wait_encrypt_prompt;
    waitforneedle("grub-reboot-windows", 25);

    sendkey "down"; sendkey "down"; sendkey "ret";
    waitforneedle("windows8", 80);    
}

1;
