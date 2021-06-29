# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2021 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

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

sub DESTROY {
    # nothing to destroy but avoid AUTOLOAD
}

# handles the attempt to invoke an undefined method on the proxy console object
# using query_isotovideo() to invoke the method on the actual console object in
# the right process
sub AUTOLOAD {
    my $function = our $AUTOLOAD;

    $function =~ s,.*::,,;

    # allow symbolic references
    no strict 'refs';
    *$AUTOLOAD = sub {
        my $self         = shift;
        my $args         = \@_;
        my $wrapped_call = {
            console   => $self->{console},
            function  => $function,
            args      => $args,
            wantarray => wantarray,
        };

        bmwqemu::log_call(wrapped_call => $wrapped_call);
        my $wrapped_retval = autotest::query_isotovideo('backend_proxy_console_call', $wrapped_call);

        if (exists $wrapped_retval->{exception}) {
            die $wrapped_retval->{exception};
        }
        # get more screenshots from consoles, especially from x3270 on s390
        $autotest::current_test->take_screenshot;

        # get more screenshots from consoles, especially from x3270 on s390
        $autotest::current_test->take_screenshot;

        return wantarray ? @{$wrapped_retval->{result}} : $wrapped_retval->{result};
    };

    goto &$AUTOLOAD;
}

1;
