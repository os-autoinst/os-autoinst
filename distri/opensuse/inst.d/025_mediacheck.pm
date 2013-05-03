use base "basetest";
use strict;
use bmwqemu;

sub is_applicable()
{
  return $ENV{MEDIACHECK};
}

sub run
{
  my $self=shift;
  sleep 40;
  waitidle(200);
  $self->check_screen; sleep 2;
  exit 0; # end test
}

1;
