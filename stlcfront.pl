#!/usr/bin/env perl

use strict;
use warnings;

use Parse::Lex;
use stlc;

my @tokens = (
    qw (
        LPAREN      [\(]
        RPAREN      [\)]
        FUN         [\\\\]
        IMP         [.]
        VAR         [A-Za-z_]+
    )
);

our $lexer = Parse::Lex->new(@tokens);
$lexer->from(\*STDIN);
$lexer->skip('\s+');

sub lexana {
    my $token = $lexer->next;
    if (not $lexer->eoi) {
        return ($token->name, $token->text);
    } else {
        return ('', undef);
    }
}

my $parser = stlc->new();
my $expr = $parser->YYParse(yylex => \&lexana);

my $type_var_idx = 0;
my %freevars;

sub new_type_var {
    {"kind" => "typevar", val => 'x'.($type_var_idx++)}
}

sub type_of_annotated {
    my $expr = shift;
    my %switches = (
        "annotated_var" => $expr->{"type"}->[1],
        "annotated_abst" => $expr->{"type"}->[2],
        "annotated_appl" => $expr->{"type"}->[2]
    );
    $switches{$expr->{"kind"}}
}

sub annotated_to_string {
    my $expr = shift;
    my %switches = (
        "annotated_var" =>
        sub {
            $expr->{"type"}->[1]->{"val"}.' '
        },
        "annotated_abst" =>
        sub {
            $expr->{"type"}->[2]->{"val"}->[0]->{"val"}."->".annotated_to_string($expr->{"type"}->[1])
        },
        "annotated_appl" =>
        sub {
            $expr->{"type"}->[2]->{"val"}.'( '.annotated_to_string($expr->{"type"}->[0]).' '.annotated_to_string($expr->{"type"}->[1]).')'
        }
    );
    $switches{$expr->{"kind"}}->()
}

sub type_annotate {
    my ($expr, $boundvars) = @_;
    my %switches = (
        "var" => 
        sub {
            my $varname = $expr->{"val"};
            my $vtype_query = sub {
                for my $elt (@$boundvars) {
                    return $elt->[1] if ($elt->[0] eq $varname);
                }
                undef
            }->();
            if (not $vtype_query) {
                $vtype_query = $freevars{$varname};
            }
            if (not $vtype_query) {
                $vtype_query = new_type_var;
                $freevars{$varname} = $vtype_query;
            }
            { "kind" => "annotated_var", "type" => [$varname, $vtype_query] }
        },
        "abst" => 
        sub {
            my ($varname, $subexpr) = @{$expr->{"val"}};
            my $vartype = new_type_var;
            unshift @$boundvars, [$varname, $vartype];
            my $absttype = type_annotate($subexpr, $boundvars);
            { 
                "kind" => "annotated_abst", 
                "type" => [$varname, $absttype, {"kind" => "functype", "val" => [$vartype, type_of_annotated($absttype)] } ] 
            }
        },
        "appl" =>
        sub {
            my ($subexpr1, $subexpr2) = @{$expr->{"val"}};
            { 
                "kind" => "annotated_appl", 
                "type" => [ 
                    type_annotate($subexpr1, $boundvars), 
                    type_annotate($subexpr2, $boundvars), 
                    new_type_var 
                ] 
            }
        }
    );
    $switches{$expr->{"kind"}}->()
}

sub collection_to_string {
    my $collection = shift;
    if (ref($collection) eq 'ARRAY') {
        my $ret = '(';
        for my $elt (@$collection) {
            $ret .= collection_to_string($elt);
        }
        return $ret.')';
    } else {
        return $collection->{"val"}.' ' if $collection->{"kind"} eq "typevar";
        return collection_to_string($collection->{"val"}) if $collection->{"kind"} eq "functype";
    }
}

sub reconstraint {
    my ($annotated_exprs, $collection) = @_;
    if (scalar @$annotated_exprs == 0) {
        return $collection;
    }
    my %switches = (
        "annotated_var" => sub { reconstraint($annotated_exprs, $collection) },
        "annotated_abst" => 
        sub {
            my $current_abst = shift;
            unshift @$annotated_exprs, $current_abst->{"type"}->[1];
            reconstraint($annotated_exprs, $collection)
        },
        "annotated_appl" => 
        sub {
            my $current_appl = shift;
            my ($derived, $base, $typev) = @{$current_appl->{"type"}};
            unshift @$annotated_exprs, $base;
            unshift @$annotated_exprs, $derived;
            unshift @$collection, [type_of_annotated($derived), { "kind" => "functype", "val" => [type_of_annotated($base), $typev] } ];
            reconstraint($annotated_exprs, $collection)
        }
    );
    my $current_expr = shift @$annotated_exprs;
    $switches{$current_expr->{"kind"}}->($current_expr)
}

#my $aexpr = type_annotate($expr, []);
#my $collection = reconstraint([$aexpr], []);

#print annotated_to_string($aexpr), "\n";
#print collection_to_string($collection), "\n";

sub occurs_in_type {
    my ($id, $type) = @_;
    my %switches = (
        "typevar" => sub { $id eq $type->{"val"} },
        "functype" =>
        sub {
            occurs_in_type($id, $type->{"val"}->[0]) or occurs_in_type($id, $type->{"val"}->[1])
        }
    );
    $switches{$type->{"kind"}}->()
}

sub subst_in_term {
    my ($subst, $varname) = @_;
    sub {
        my ($origin) = @_;
        my %switches = (
            "typevar" => sub { ($varname eq $origin->{"val"}) ? $subst : $origin },
            "functype" => 
            sub { 
                { 
                    "kind" => "functype", 
                    "val" => [ 
                        subst_in_term($subst, $varname)->($origin->{"val"}->[0]), 
                        subst_in_term($subst, $varname)->($origin->{"val"}->[1])
                    ] 
                } 
            }
        );
        $switches{$origin->{"kind"}}->()
    }
}

sub apply_substitution {
    my ($subst, $type) = @_;
    sub {
        my ($f, $b, $l) = @_;
        for my $e (reverse @$l) {
            $b = $f->($e)->($b);
        }
        $b
    }->(sub { my ($x) = @_; subst_in_term($x->[1], $x->[0]) }, $type, $subst)
}

sub unify;
sub unify_pair;

sub unify_pair {
    my ($s, $t) = @_;
    my $unify_tvar_func = 
    sub { 
        my ($tvar, $func) = @_; 
        sub {
            die "not unifiable" if (occurs_in_type($tvar->{"val"}, $func));
            [ [$tvar->{"val"}, $func] ]
        } 
    };
    my %switches = (
        "typevar typevar" => sub { ($s->{"val"} eq $t->{"val"}) ? [] : [ [$s->{"val"}, $t] ] },
        "functype functype" => 
        sub {
            unify([ [$s->{"val"}->[0], $t->{"val"}->[0]], [$s->{"val"}->[1], $s->{"val"}->[1]] ])
        },
        "typevar functype" => $unify_tvar_func->($s, $t),
        "functype typevar" => $unify_tvar_func->($t, $s)
    );
    $switches{$s->{"kind"}.' '.$t->{"kind"}}->()
}

sub concat {
    my @list_of_lists = @_;
    my @list;

    for my $elt (@list_of_lists) {
        push @list, $_ for @$elt;
    }
    \@list
}

sub unify {
    my $type_rels = shift;
    if (scalar @$type_rels == 0) {
        return [];
    }
    my $rel = shift @$type_rels;
    my $unifier = unify($type_rels);
    my $unifier_ = unify_pair(apply_substitution($unifier, $rel->[0]), apply_substitution($unifier, $rel->[1]));
    concat($unifier_, $unifier)
}

sub infer {
    my $expr = shift;
    my $aexpr = type_annotate($expr, []);
    my $collection = reconstraint([$aexpr], []);
    my $unifiers = unify($collection);
    # XXX it seems that we've got a correct collection of MGUs
    apply_substitution($unifiers, type_of_annotated($aexpr))
}

sub type_to_string {
    my $type = shift;
    my %switches = (
        "typevar" => sub { $type->{"val"} },
        "functype" =>
        sub {
            if ($type->{"val"}->[0]->{"kind"} eq "typevar") {
                return type_to_string($type->{"val"}->[0]).'->'.type_to_string($type->{"val"}->[1]);
            } else {
                return '('.type_to_string($type->{"val"}->[0]).')'.'->'.type_to_string($type->{"val"}->[1]);
            }
        }
    );
    $switches{$type->{"kind"}}->()
}

my $res = infer($expr);
print type_to_string($res), "\n";
