package commands;

use threads;
use threads::shared;

# Automatically enables "strict", "warnings", "utf8" and Perl 5.10 features
use Mojolicious::Lite;
use Mojo::IOLoop;
use Mojo::Server::Daemon;

sub run_daemon {
  my ($port) = @_;

  print "PORT $port\n";

  #$daemon->unsubscribe('request');
  get '/' => { text => 'Hello World!' };

  my $daemon = Mojo::Server::Daemon->new(app => app, listen => ["http://*:$port"]);
 
  $daemon->run;

}

sub start_server($) {
  my ($port) = @_;

  my $thr = threads->create(\&run_daemon, $port);
  return $thr;
}

1;
