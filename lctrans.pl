#!/usr/bin/perl

# These are only decoration. The superiors hardly understand this.

use strict;
use warnings;

use Parse::Lex;
use lc2pl;

my @tokens = (
    qw (
        LPAREN      [\(]
        RPAREN      [\)]
        FUN         [\\\\]
        IMP         [.]
        VAR         [A-Za-z_][A-Za-z_0-9]*
        CONST       [1-9][0-9]*
    )
);

our $lexer = Parse::Lex->new(@tokens);
$lexer->skip('\s+');

sub lexana {
    my $token = $lexer->next;
    if (not $lexer->eoi) {
        return ($token->name, $token->text);
    } else {
        return ('', undef);
    }
}

# $lexer->from(\*STDIN);
$lexer->from('\f.(\x.(f (\y.x x y))) (\x.(f (\y.x x y)))');

my $parser = lc2pl->new();
my $expr = $parser->YYParse(yylex => \&lexana);

#print $expr->(), "\n";

# \f.\x.(=0 x) 1 (* x (f (- x 1)))
sub fac {
    my $f = shift;
    sub {
        my $x = shift;
        ($x) ? ($x * $f->($x - 1)) : (1)
    }
}

# \f.(\x.(f (\y.x x y))) (\x.(f (\y.x x y)))
print $expr->()->(\&fac)->(5), "\n";
