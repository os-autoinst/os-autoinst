# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2020 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# This is the direct companion to backend::proxy_console_call()
#
# "console_proxy" is a proxy object for calls to specific terminal functions
# like s3270->... or vnc->... or ssh->... from the tests in the main
# thread.

package backend::console_proxy;

use Mojo::Base -strict, -signatures;
use feature 'say';

sub new ($class, $console) {
    my $self = bless({class => $class, console => $console}, $class);
    return $self;
}

# nothing to destroy but avoid AUTOLOAD
sub DESTROY () { }

# handles the attempt to invoke an undefined method on the proxy console object
# using query_isotovideo() to invoke the method on the actual console object in
# the right process
sub AUTOLOAD {    # no:style:signatures
    my $function = our $AUTOLOAD;

    $function =~ s,.*::,,;

    # allow symbolic references
    no strict 'refs';
    *$AUTOLOAD = sub {    # no:style:signatures
        my $self = shift;
        my $args = \@_;
        my $wrapped_call = {
            console => $self->{console},
            function => $function,
            args => $args,
            wantarray => wantarray,
        };

        bmwqemu::log_call(wrapped_call => $wrapped_call);
        my $wrapped_retval = autotest::query_isotovideo('backend_proxy_console_call', $wrapped_call);
        die $wrapped_retval->{exception} if exists $wrapped_retval->{exception};

        # get more screenshots from consoles, especially from x3270 on s390
        $autotest::current_test->take_screenshot;

        # get more screenshots from consoles, especially from x3270 on s390
        $autotest::current_test->take_screenshot;

        return wantarray ? @{$wrapped_retval->{result}} : $wrapped_retval->{result};
    };

    # this is why we can't use a signature for this function, goto
    # implicitly uses @_ and that triggers a warning in a function
    # with a signature. We want to use goto to hide frames in stack
    # traces (per @kraih)
    goto &$AUTOLOAD;
}

1;
