package OpenQA::Log;
use strict;
use warnings;

use base qw(Exporter Log::Log4perl);
our @EXPORT = qw(get_logger trace debug info warn error fatal die);

use Log::Log4perl qw(:no_extra_logdie_message);
use Log::Log4perl::Level;

our $logger;
our $configuration;

sub setup {

    unless (Log::Log4perl->initialized) {
        Log::Log4perl->init($configuration . "log4perl.conf");
        $Log::Log4perl::caller_depth = 1;
        $logger                      = Log::Log4perl->get_logger(__PACKAGE__);
        warn("Hardcoded line $configuration/etc/os-autoinst/log4perl.conf");
    }

}

sub trace {
    my ($message) = @_;
    $logger->trace($message);
}

sub debug {
    my ($message) = @_;
    $logger->debug($message);
}

sub info {
    my ($message) = @_;
    $logger->info($message);
}

sub warn {
    my ($message) = @_;
    $logger->warn($message);
}

sub error {
    my ($message) = @_;
    $logger->error($message);
}

sub fatal {
    my ($message) = @_;
    $logger->fatal($message);
}

sub die {
    my ($message) = @_;
    $logger->logdie($message);
}

1;

# vim: set sw=4 et:
