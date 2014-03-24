#!/usr/bin/env perl

use strict;
use warnings;

use Parse::Lex;
use utlc;
use HOI::Match;

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

my $parser = utlc->new();
my $expr = $parser->YYParse(yylex => \&lexana);

sub ast_to_string;

sub var_to_string {
    my ($varval) = @_;
    $varval
}

sub abst_to_string {
    my ($boundvar, $term) = @_;
    "\\".$boundvar.'.'.ast_to_string($term)
}

sub appl_to_string {
    my ($op, $arg) = @_;
    '('.ast_to_string($op).' '.ast_to_string($arg).')'
}

sub ast_to_string {
    HOI::Match::pmatch(
        "var (val)" => sub { my %args = @_; var_to_string($args{val}) },
        "abst (boundvar term)" => sub { my %args = @_; abst_to_string($args{boundvar}, $args{term}) },
        "appl (op arg)" => sub { my %args = @_; appl_to_string($args{op}, $args{arg}) },
        "appl (op arg _dup)" => sub { my %args = @_; appl_to_string($args{op}, $args{arg}) },
    )->(@_)
}

my %symcnt = ();
sub gensym {
    my ($prefix) = @_;
    $symcnt{$prefix} = 0 if (not defined $symcnt{$prefix});
    $prefix.($symcnt{$prefix}++)
}

sub var_any {
    my ($val) = @_;
    { "type" => "var", "val" => [ $val ] }
}

sub abst_any {
    my ($boundvar, $term) = @_;
    { "type" => "abst", "val" => [ $boundvar, $term ] }
}

sub appl_any {
    my ($op, $arg, $dup) = @_;
    (defined($dup)) ? { "type" => "appl", "val" => [ $op, $arg, 1 ] } : { "type" => "appl", "val" => [ $op, $arg ] }
}

sub do_rewrite;

sub do_rewrite_appl {
    my ($op, $arg, $cntx) = @_;
    HOI::Match::pmatch(
        "abst (op_bvar op_term), any" => 
        sub { 
            my %args = @_; 
            my $cntx_current = { %$cntx };
            my $arg_rewritten = do_rewrite($args{any}, $cntx_current); 
            $cntx_current->{$args{op_bvar}} = $arg_rewritten;
            do_rewrite($args{op_term}, $cntx_current)
        },
        "appl (op arg), arg_any" => 
        sub { 
            my %args = @_; 
            do_rewrite_appl(do_rewrite_appl($args{op}, $args{arg}, $cntx), $args{arg_any}, $cntx) 
        },
        "appl (op arg _dup), arg_any" => 
        sub { 
            my %args = @_; 
            appl_any(appl_any(do_rewrite($args{op}, $cntx), do_rewrite($args{arg}, $cntx), 1), do_rewrite($args{arg_any}, $cntx))
        },
        "var (val1), var (val2)" =>
        sub {
            my %args = @_;
            my @rewritten = (do_rewrite(var_any($args{val1}), $cntx), do_rewrite(var_any($args{val2}), $cntx));
            if ( ($rewritten[0]->{type} eq 'var') && ($rewritten[1]->{type} eq 'var') &&
                 ($args{val1} eq $rewritten[0]->{val}->[0]) && ($args{val2} eq $rewritten[1]->{val}->[0]) ) {
                appl_any(@rewritten, 1)
            } else {
                return do_rewrite_appl(@rewritten, $cntx);
            }
        },
        "var (val), arg_any" => 
        sub { 
            my %args = @_; 
            my $rewritten = do_rewrite(var_any($args{val}), $cntx);
            if ( ($rewritten->{type} eq 'var') && ($args{val} eq $rewritten->{val}->[0]) ) {
                return appl_any($rewritten, do_rewrite($args{arg_any}, $cntx));
            } else {
                return do_rewrite_appl($rewritten, $args{arg_any}, $cntx);
            }
        },
    )->($op, $arg)
}

sub do_rewrite {
    my ($ast, $cntx) = @_;
    HOI::Match::pmatch(
        "var (val)" => sub { my %args = @_; (defined $cntx->{$args{val}}) ? $cntx->{$args{val}} : var_any($args{val}) },
        "abst (boundvar term)" =>
        sub {
            my %args = @_; 
            my $cntx_current = { %$cntx };
            abst_any($args{boundvar}, do_rewrite($args{term}, $cntx_current)) 
        },
        "appl (op arg)" => sub { my %args = @_; do_rewrite_appl($args{op}, $args{arg}, $cntx) },
        "appl (op arg _dup)" => 
        sub { 
            my %args = @_; 
            appl_any(do_rewrite($args{op}, $cntx), do_rewrite($args{arg}, $cntx), 1);
        }
    )->($ast)
}

sub cpstrans {
    HOI::Match::pmatch(
        "var (val)" => sub { my %args = @_; my $cont = gensym("c"); abst_any($cont, appl_any(var_any($cont), var_any($args{val}))) },
        "abst (boundvar term)" => 
        sub { 
            my %args = @_; 
            my ($cont, $cont2, $contarg) = (gensym("c"), gensym("k"), gensym("m"));
            abst_any($cont, appl_any(var_any($cont), abst_any($args{boundvar}, abst_any($cont2, appl_any(cpstrans($args{term}), abst_any($contarg, appl_any(var_any($cont2), var_any($contarg))))))))
        },
        "appl (op arg)" => 
        sub {
            my %args = @_; 
            my ($cont, $cont2, $cont3, $contarg) = (gensym("c"), gensym("m"), gensym("n"), gensym("a"));
            abst_any($cont, appl_any(cpstrans($args{op}), abst_any($cont2, appl_any(cpstrans($args{arg}), abst_any($cont3, appl_any(appl_any(var_any($cont2), var_any($cont3)), abst_any($contarg, appl_any(var_any($cont), var_any($contarg)))))))))
        },
        "appl (op arg _dup)" => 
        sub {
            my %args = @_; 
            my ($cont, $cont2, $cont3, $contarg) = (gensym("c"), gensym("m"), gensym("n"), gensym("a"));
            abst_any($cont, appl_any(cpstrans($args{op}), abst_any($cont2, appl_any(cpstrans($args{arg}), abst_any($cont3, appl_any(appl_any(var_any($cont2), var_any($cont3)), abst_any($contarg, appl_any(var_any($cont), var_any($contarg)))))))))
        }
    )->(@_)
}

my $cpsform = cpstrans(do_rewrite($expr, {}));
print ast_to_string($cpsform), "\n";
print ast_to_string(do_rewrite($cpsform, {})), "\n";
