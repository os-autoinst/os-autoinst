package Perl::Critic::Policy::HashKeyQuotes;

use Mojo::Base 'Perl::Critic::Policy', -signatures;
use Perl::Critic::Utils qw( :severities :classification :ppi );

our $VERSION = '0.0.1';

sub default_severity (@) { $SEVERITY_HIGH }
sub default_themes (@) { qw(openqa) }
sub applies_to (@) { qw(PPI::Token::Quote::Single PPI::Token::Quote::Double) }

# check that hashes are not overly using quotes
# (os-autoinst coding style)

sub violates ($self, $elem, $) {
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
