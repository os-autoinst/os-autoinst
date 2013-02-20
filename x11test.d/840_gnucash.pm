use base "basetest";
use bmwqemu;

sub run()
{
  my $self=shift;
  ensure_installed("gnucash");
  x11_start_program("gnucash");
  $self->take_screenshot;
  sendkey "alt-o"; # open new user tutorial
  sendkey "spc";
  sendkey "alt-o";
  sendkey "spc";
  sendkey "f1"; # open Help
  $self->take_screenshot;
  sendkey "alt-f4"; # Exit
}

1;
