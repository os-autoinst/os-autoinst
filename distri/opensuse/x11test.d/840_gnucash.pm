use base "basetest";
use bmwqemu;

sub run()
{
  my $self=shift;
  ensure_installed("gnucash");
  x11_start_program("gnucash");
  $self->check_screen;
  sendkey "alt-o"; # open new user tutorial
  sendkey "spc";
  sendkey "alt-o";
  sendkey "spc";
  sendkey "f1"; # open Help
  $self->check_screen;
  sendkey "alt-f4"; # Exit
}

1;
