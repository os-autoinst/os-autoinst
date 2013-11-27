use base "basetest";
use bmwqemu;

sub run()
{
  my $self=shift;
  ensure_installed("gnucash");
  ensure_installed("gnucash-docs");
  x11_start_program("gnucash");
  $self->check_screen;
  sendkey "alt-o"; # open new user tutorial
  sendkey "spc";
  sendkey "alt-o";
  sendkey "spc";
  waitidle;
  $self->check_screen;
  sendkey "alt-f4"; # Leave tutorial window
  sleep 2;
  # Leave tips windows for GNOME case
  if($ENV{GNOME}) { sendkey "alt-c"; sleep 2; }
  sendkey "ctrl-q"; # Exit
}

1;
