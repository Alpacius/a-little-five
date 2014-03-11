#!/usr/bin/env perl

use strict;
use warnings;

use Parse::Lex;
use hmlc;

my @tokens = (
    qw (
        LPAREN      [\(]
        RPAREN      [\)]
        FUN         [\\\\]
        IMP         [.]
        LET         let
        LETREC      rec
        EQ          [=]
        IN          in
        END         end
        VAR         [A-Za-z_]+
    ),
    COMMA => q/,/
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

my $parser = hmlc->new();
my $expr = $parser->YYParse(yylex => \&lexana);

my $typevar_idx = 0;

sub new_typevar {
    { "kind" => "typevar", "val" => 'x'.($typevar_idx++) }
}

sub new_typeappl {
    { "kind" => "typeappl", "val" => { "oper" => $_[0], "args" => $_[1] } }
}

sub type_to_string {
    my $type = shift;
    my %switches = (
        "typevar" => sub { ($type->{"inst"}) ? type_to_string($type->{"inst"}) : $type->{"val"} },
        "typeappl" => 
        sub {
            if ($#{$type->{"val"}->{"args"}} == 1) {
                return '('.type_to_string($type->{"val"}->{"args"}->[0]).' '.$type->{"val"}->{"oper"}.' '.type_to_string($type->{"val"}->{"args"}->[1]).')';
            } elsif ($#{$type->{"val"}->{"args"}} < 0){
                return $type->{"val"}->{"oper"};
            } else {
                my $ret = '( '.$type->{"val"}->{"oper"}.' ';
                for my $elt (@{$type->{"val"}->{"args"}}) {
                    $ret .= type_to_string($elt).' ';
                }
                return $ret.')';
            }
        }
    );
    $switches{$type->{"kind"}}->()
}

sub occurs_in_type {
    my ($tv, $t) = @_;
    my %switches = (
        "typevar" => sub { $tv->{"val"} eq $t->{"val"} },
        "typeappl" => sub { scalar grep { occurs_in_type($tv, $_) } @{$t->{"val"}->{"args"}} }
    );
    $switches{$t->{"kind"}}->()
}

sub obtain_typevar_in_env {
    my ($type, $env) = @_;
    $env->{$type} = new_typevar() unless $env->{$type};
    $env->{$type}
}

sub obtain_type_in_env {
    my ($type, $env, $free_typevars) = @_;
    $type = find($type);
    my %switches = (
        "typevar" => sub { (scalar grep { occurs_in_type($type, $_) } @$free_typevars) ? $type : obtain_typevar_in_env($type, $env) },
        "typeappl" => 
        sub {
            new_typeappl($type->{"val"}->{"oper"}, [ map { obtain_type_in_env($_, $env, $free_typevars) }  @{$type->{"val"}->{"args"}} ])
        }
    );
    $switches{$type->{"kind"}}->()
}

sub inst {
    my ($typename, $env, $free_typevars) = @_;
    my $type = $env->{$typename};
    die "undefined type: $typename" unless (defined $type);
    $type = obtain_type_in_env($type, {}, $free_typevars);
    $type
}

sub find {
    my $type = shift;
    if ($type->{"kind"} eq "typevar") {
        if (defined $type->{"inst"}) {
            $type->{"inst"} = find($type->{"inst"});
            return $type->{"inst"};
        }
    }
    $type
}

sub unify {
    my ($type1, $type2, $free_typevars) = @_;
    ($type1, $type2) = (find($type1), find($type2));
    my $check_and_union = 
    sub { 
        my ($t1, $t2) = @_; 
        sub { 
            die "recursive unification" if ($t1 != $t2 && occurs_in_type($t1, $t2));
            $t1->{"inst"} = $t2;
        } 
    };
    my %switches = (
        #"typevar typevar" => $check_and_union->($type1, $type2),
        "typevar typevar" => 
        sub { 
            if ((scalar grep { occurs_in_type($type1, $_) } @$free_typevars) &&
               !(scalar grep { occurs_in_type($type2, $_) } @$free_typevars)) {
               unify($type2, $type1, $free_typevars)
            } else {
                $check_and_union->($type1, $type2)->()
            }
        },
        "typevar typeappl" => $check_and_union->($type1, $type2),
        "typeappl typevar" => $check_and_union->($type2, $type1),
        "typeappl typeappl" => 
        sub {
            die "operator mismatch: $type1->{val}->{oper} - $type2->{val}->{oper}" if ($type1->{"val"}->{"oper"} ne $type2->{"val"}->{"oper"});
            die "arith mismatch" if ($#{$type1->{"val"}->{"args"}} != $#{$type2->{"val"}->{"args"}});
            for (my $idx = 0; $idx <= $#{$type1->{"val"}->{"args"}}; $idx++) {
                unify($type1->{"val"}->{"args"}->[$idx], $type2->{"val"}->{"args"}->[$idx], $free_typevars);
            }
        }
    );
    $switches{$type1->{"kind"}.' '.$type2->{"kind"}}->()
}

sub algorithm_w {
    my ($expr, $env, $free_typevars) = @_;
    my %switches = (
        "var" => sub { inst($expr->{"val"}, $env, $free_typevars) },
        "abst" => 
        sub {
            my $env_current = { %$env };
            my $arg_type = new_typevar();
            $env_current->{$expr->{"val"}->[0]} = $arg_type;
            my $free_typevars_current = [ @$free_typevars ];
            push @$free_typevars_current, $arg_type;
            my $body_type =  algorithm_w($expr->{"val"}->[1], $env_current, $free_typevars_current);
            new_typeappl("->", [ $arg_type, $body_type ])
        },
        "appl" =>
        sub {
            my ($func_type, $arg_type) = 
            (algorithm_w($expr->{"val"}->[0], $env, $free_typevars),
             algorithm_w($expr->{"val"}->[1], $env, $free_typevars));
            my $ret = new_typevar(); 
            # XXX Here we pollute $free_typevars. $ret should be free.
            #     It does not matter that we pollute the "global" ftv list. We will not keep it.
            push @$free_typevars, $ret;
            unify(new_typeappl("->", [ $arg_type, $ret ]), $func_type, $free_typevars);
            $ret
        },
        "let" =>
        sub {
            my $defn_type = algorithm_w($expr->{"val"}->[1], $env, $free_typevars);
            my $env_current = { %$env };
            $env_current->{$expr->{"val"}->[0]} = $defn_type;
            algorithm_w($expr->{"val"}->[2], $env_current, $free_typevars)
        },
        "letrec" =>
        #sub {
        #    my ( $env_current, $free_typevars_current ) = 
        #       ( { %$env }, [ @$free_typevars ] );
        #    my $defn_vartype = new_typevar();
        #    $env_current->{$expr->{"val"}->[0]} = $defn_vartype;
        #    push @$free_typevars_current, $defn_vartype;
        #    my $defn_type = algorithm_w($expr->{"val"}->[1], $env_current, $free_typevars_current);
        #    # XXX Remove $defn_vartype from foralls. Now it's higher-order polymorphism.
        #    my($rmidx)= grep { $free_typevars_current->[$_] eq $defn_vartype } 0..$#{$free_typevars_current};
        #    splice @$free_typevars_current, $rmidx, 1;
        #    unify($defn_vartype, $defn_type, $free_typevars_current);
        #    algorithm_w($expr->{"val"}->[2], $env_current, $free_typevars_current)
        #}
        # Here we are able to handle mutral recursion. 
        # Or we should say that self-recursion is trivial. I keep the old code for reference on the algorithm.
        sub {
            my ( $env_current, $free_typevars_current ) = 
               ( { %$env }, [ @$free_typevars ] );
            my @lhslist = ();
            my $defns = $expr->{"val"}->[0];
            for my $elt (@$defns) {
                my $defn_vartype = new_typevar();
                push @lhslist, $defn_vartype;
                $env_current->{$elt->[0]} = $defn_vartype;
                push @$free_typevars_current, $defn_vartype;
            }
            for my $elt (@$defns) {
                my $defn_vartype = $env_current->{$elt->[0]};
                my $defn_type = algorithm_w($elt->[1], $env_current, $free_typevars_current);
                unify($defn_vartype, $defn_type, $free_typevars_current);
            }
            for my $lhsvar (@lhslist) {
                my($rmidx)= grep { $free_typevars_current->[$_] eq $lhsvar } 0..$#{$free_typevars_current};
                splice @$free_typevars_current, $rmidx, 1;
            }
            algorithm_w($expr->{"val"}->[1], $env_current, $free_typevars_current)
        }
    );
    $switches{$expr->{"kind"}}->()
}

my $langenv = {};

my ($type_var_pairelt1, $type_var_pairelt2) = (new_typevar(), new_typevar());
my $pair_type = new_typeappl('*', [ $type_var_pairelt1, $type_var_pairelt2 ]);
$langenv->{"pair"} = new_typeappl("->", [ $type_var_pairelt1, new_typeappl("->", [ $type_var_pairelt2, $pair_type ]) ] );
$langenv->{"prea"} = new_typeappl("Int", []);
$langenv->{"preb"} = new_typeappl("Bool", []);
$langenv->{"add"} = new_typeappl("->", [ new_typeappl("Int", []), new_typeappl("->", [ new_typeappl("Int", []), new_typeappl("Int", []) ]) ]);

while (my ($k, $v) = each %$langenv) {
    print "$k :: ".type_to_string($v)."\n";
}

my $res = algorithm_w($expr, $langenv, []);
print type_to_string($res), "\n";
