package Perl::Critic::Policy::HashKeyQuotes;

use Mojo::Base -strict, -signatures;

use Perl::Critic::Utils qw( :severities :classification :ppi );
use base 'Perl::Critic::Policy';

our $VERSION = '0.0.1';

sub default_severity { return $SEVERITY_HIGH }
sub default_themes   { return qw(openqa) }
sub applies_to       { return qw(PPI::Token::Quote::Single PPI::Token::Quote::Double) }

# check that hashes are not overly using quotes
# (os-autoinst coding style)

sub violates ($self, $elem) {
    #we only want the check hash keys
    return if !is_hash_key($elem);

    my $c = $elem->content;
    # Quotes allowed, if not matching following regex
    return unless $c =~ m/^(["'])[a-zA-Z][0-9a-zA-Z]*\1$/;

    my $desc = qq{Hash key $c with quotes};
    my $expl = q{Avoid useless quotes};
    return $self->violation($desc, $expl, $elem);
}

1;
