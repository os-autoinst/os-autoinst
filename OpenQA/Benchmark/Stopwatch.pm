package OpenQA::Benchmark::Stopwatch;

use Mojo::Base -strict, -signatures;

our $VERSION = '0.05';
use Time::HiRes;

=head1 NAME

Benchmark::Stopwatch - simple timing of stages of your code.

=head1 SYNOPSIS

    use Benchmark::Stopwatch;
    my $stopwatch = Benchmark::Stopwatch->new->start;

    # ... code that reads from database ...
    $stopwatch->lap('read from database');

    # ... code that writes to disk ...
    $stopwatch->lap('write to disk');

    print $stopwatch->stop->summary;

    # NAME                        TIME        CUMULATIVE      PERCENTAGE
    #  read from database          0.123       0.123           34.462%
    #  write to disk               0.234       0.357           65.530%
    #  _stop_                      0.000       0.357           0.008%

=head1 DESCRIPTION

The other benchmark modules provide excellent timing for specific parts of
your code. This module aims to allow you to easily time the progression of
your code.

The stopwatch analogy is that at some point you get a C<new> stopwatch and
C<start> timing. Then you note certain events using C<lap>. Finally you
C<stop> the watch and then print out a C<summary>.

The summary shows all the events in order, what time they occurred at, how long
since the last lap and the percentage of the total time. Hopefully this will
give you a good idea of where your code is spending most of its time.

The times are all wallclock times in fractional seconds.

That's it.

=head1 METHODS

=head2 new

    my $stopwatch = Benchmark::Stopwatch->new;

Creates a new stopwatch.

=cut

sub new ($class) {
    my $self = {};

    $self->{events} = [];
    $self->{_time}  = sub { Time::HiRes::time() };
    $self->{length} = 26;

    return bless $self, $class;
}

=head2 start

    $stopwatch = $stopwatch->start;

Starts the stopwatch. Returns a reference to the stopwatch so that you can
chain.

=cut

sub start ($self) {
    $self->{start} = $self->time;
    return $self;
}

=head2 lap

    $stopwatch = $stopwatch->lap( 'name of event' );

Notes down the time at which an event occurs. This event will later appear in
the summary.

=cut

sub lap ($self, $name) {
    my $time        = $self->time;
    my $name_lenght = length $name;
    $self->{length} = $name_lenght if $name_lenght > $self->{length};
    push @{$self->{events}}, {name => $name, time => $time};
    return $self;
}

=head2 stop

    $stopwatch = $stopwatch->stop;

Stops the stopwatch. Returns a reference to the stopwatch so you can chain.

=cut

sub stop ($self) {
    $self->{stop} = $self->time;
    return $self;
}

=head2 total_time

    my $time_in_seconds = $stopwatch->total_time;

Returns the time that the stopwatch ran for in fractional seconds. If the
stopwatch has not been stopped yet then it returns time it has been running
for.

=cut

sub total_time ($self) {
    # Get the stop time or now if missing.
    my $stop = $self->{stop} || $self->time;

    return $stop - $self->{start};
}

=head2 summary

    my $summary_text = $stopwatch->summary;

Returns text summarizing the events that occurred. Example output from a script
that fetches the homepages of the web's five busiest sites and times how long
each took.

 NAME                        TIME        CUMULATIVE      PERCENTAGE
  http://www.yahoo.com/       3.892       3.892           22.399%
  http://www.google.com/      3.259       7.152           18.758%
  http://www.msn.com/         8.412       15.564          48.411%
  http://www.myspace.com/     0.532       16.096          3.062%
  http://www.ebay.com/        1.281       17.377          7.370%
  _stop_                      0.000       17.377          0.000%

The final entry C<_stop_> is when the stop watch was stopped.

=cut

sub summary ($self) {
    my $out           = '';
    my $header_format = "%-$self->{length}.$self->{length}s %-11s %-15s %s\n";
    my $result_format = " %-$self->{length}.$self->{length}s %-11.3f %-15.3f %.3f%%\n";
    my $prev_time     = $self->{start};
    push @{$self->{events}}, {name => '_stop_', time => $self->{stop}};

    $out .= sprintf $header_format, qw( NAME TIME CUMULATIVE PERCENTAGE);

    foreach my $event (@{$self->{events}}) {

        my $duration   = $event->{time} - $prev_time;
        my $cumulative = $event->{time} - $self->{start};
        my $percentage = ($duration / $self->total_time) * 100;

        $out .= sprintf $result_format,    #
          $event->{name},                  #
          $duration,                       #
          $cumulative,                     #
          $percentage;

        $prev_time = $event->{time};
    }

    pop @{$self->{events}};
    return $out;
}

=head2 as_data

  my $data_structure_hashref = $stopwatch->as_data;

Returns a data structure that contains all the information that was logged.
This is so that you can use this module to gather the data but then use your
own code to manipulate it.

The returned hashref will look like this:

  {
    start_time => 1234500,  # The time the stopwatch was started
    stop_time  => 1234510,  # The time it was stopped or as_data called
    total_time => 10,       # The duration of timing
    laps       => [
        {
            name       => 'test', # The name of the lap
            time       => 1,      # The time of this lap (seconds)
            cumulative => 1,      # seconds since start to this lap
            fraction   => 0.10,   # fraction of total time.
        },
        {
            name       => '_stop_',   # created as needed
            time       => 9,
            cumulative => 10,
            fraction   => 0.9,
        },
    ],
  }

=cut

sub as_data ($self) {
    my %data = ();

    $data{start_time} = $self->{start};
    $data{stop_time}  = $self->{stop} || $self->time;
    $data{total_time} = $data{stop_time} - $data{start_time};

    # Clone the events across and add the stop event.
    # $data{laps} = clone($self->{events});
    my @laps = @{$self->{events}};
    push @laps, {name => '_stop_', time => $data{stop_time}};

    # For each entry in laps calculate the cumulative and the fraction.
    my $running_total = 0;
    my $last_time     = $data{start_time};
    foreach my $lap (@laps) {
        my %lapcopy   = %$lap;
        my $this_time = delete $lapcopy{time};
        $lapcopy{time} = $this_time - $last_time;
        $last_time = $this_time;

        $running_total += $lapcopy{time};
        $lapcopy{cumulative} = $running_total;
        $lapcopy{fraction}   = $lapcopy{time} / $data{total_time};

        push @{$data{laps}}, \%lapcopy;
    }

    return \%data;
}

sub time {
    &{$_[0]{_time}};
}

=head1 AUTHOR

Edmund von der Burg C<<evdb@ecclestoad.co.uk>>

L<http://www.ecclestoad.co.uk>

=head1 ACKNOWLEDGMENTS

Inspiration from my colleagues at L<http://www.nestoria.co.uk>

=head1 COPYRIGHT

Copyright (C) 2006 Edmund von der Burg. All rights reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself. If it breaks you get to keep both pieces.

THERE IS NO WARRANTY.

=cut

1;
