#!/usr/bin/env perl

use strict;

{
    package wraith;

    {
        package inner_lazy;

        sub TIESCALAR {
            my ($class, $val) = @_;
            bless $_[1], $class
        }

        sub FETCH {
            my ($self) = @_;
            $self->()
        }
    }

    use overload
        '>>' => "then_impl",
        '|' => "alt_impl",
        '**' => "using_impl";

    sub deref {
        my @args = @_;
        for my $elt (@args) {
            if (ref($elt) eq "wraith_rule") {
                $elt = $$elt;
            }
        }
        @args
    }

    our $concat =
    sub {
        my @list_of_lists = @_;
        my @list;

        for my $elt (@list_of_lists) {
            push @list, $_ for @$elt;
        }
        \@list
    };

    our $succeed = 
    bless
    sub {
        my $v = $_[0];
        bless
        sub {
            my $u = (ref($v) eq "ARRAY") ? $v : [ $v ];
            [ [ $u, $_[0] ] ]
        }
    };

    our $fail = 
    bless
    sub {
        []
    };

    our $satisfy = 
    bless
    sub {
        my ($p, $m) = @_;
        $m = sub { $_[0] =~ /(.)(.*)/s } if not $m;
        bless
        sub {
            if (my ($x, $xs) = $m->($_[0])) {
                if ($p->($x)) {
                    return $succeed->($x)->($xs);
                } else {
                    return $fail->($xs);
                }
            } else {
                return $fail->( [] );
            }
        }
    };

    our $literal = 
    bless
    sub {
        my $y = $_[0];
        $satisfy->( 
            sub { 
                $y eq $_[0] 
            }
        )
    };

    our $literals = 
    bless
    sub {
        my $y = $_[0];
        $satisfy->(
            sub {
                index($y, $_[0]) != -1
            }
        )
    };

    our $token =
    bless 
    sub {
        my ($tok, $skip) = @_;
        $skip = '\s*' if not $skip;
        $satisfy->(
            sub { 1 },
            sub {
                #print "match: $tok\n";
                $_[0] =~ /^$skip($tok)(.*)/s
            }
        )
    };

    sub alt_impl {
        my ($p1_, $p2_, $discard) = @_;
        bless
        sub {
            my ($p1, $p2) = deref($p1_, $p2_);
            my $inp = $_[0];
            $concat->($p1->($inp), $p2->($inp))
        }
    }
    our $alt = bless \&alt_impl;

    sub then_impl {
        my $arglist = \@_;
        bless
        sub {
            my ($p1) = deref($arglist->[0]);
            my $inp = $_[0];
            my $reslist1 = $p1->($inp);
            my $finlist = [];
            for my $respair (@$reslist1) {
                my ($p2) = deref($arglist->[1]);
                my $reslist2 = $p2->($respair->[1]);
                for my $finpair (@$reslist2) {
                    push @$finlist, [ $concat->($respair->[0], $finpair->[0]), $finpair->[1] ];
                }
            }
            $finlist
        }
    }
    our $then = bless \&then_impl;

    sub using_impl {
        my ($p_, $f, $discard) = @_;
        bless
        sub {
            my ($p) = deref($p_);
            my $inp = $_[0];
            my $reslist = $p->($inp);
            my $finlist = [];
            for my $respair (@$reslist) {
                push @$finlist, [ $f->($respair->[0]), $respair->[1] ];
            }
            $finlist
        }
    }
    our $using = bless \&using_impl;

    sub many_impl {
        # XXX bug at 10th then (2nd many)
        # XXX fix by remove dereference
        #my ($p) = deref($_[0]);
        my $p = $_[0];
        my $f;
        tie $f, "inner_lazy", sub { many_impl($p) };
        $alt->($then->($p, $f), $succeed->( [] ))
    }
    our $many = bless \&many_impl;
}

{
    package wraith_rule;

    our @ISA = qw ( wraith );

    sub makerule {
        bless $_[0]
    }

    sub makerules {
        my ($class, @args) = @_;
        for my $elt (@args) {
            $elt = makerule($elt);
        }
        @args
    }
}

# test case: a lambda-calculus-to-perl translator

my %expr_root = ( "kind" => "list", "defn" => [], "term" => [] );
my $rootref = \%expr_root;

my ($formlist, $form, $term, $varlist, $appterm, $aterm);
wraith_rule->makerules(\$formlist, \$form, \$term, \$varlist, \$appterm, \$aterm);

$formlist = $wraith::many->(\$form); # 1
$form = ( (\$term >> $wraith::token->(';')) ** # 2
            sub { 
                [ { "kind" => "term", "body" => $_[0]->[0] } ]
            } 
        ) | 
        ( ($wraith::token->('[A-Za-z_]+') >> $wraith::token->('=') >> \$term >> $wraith::token->(';')) ** # 345
            sub {
                [ { "kind" => "defn", "name" => $_[0]->[0], "body" => $_[0]->[2] } ]
            } 
        );
$term = ( (\$appterm) ** sub { [ { "kind" => "appl", "body" => $_[0]->[0] } ] } ) |
        ( ($wraith::token->('\\\\') >> \$varlist >> $wraith::token->('\.') >> \$term) ** # 678
            sub {
                [ { "kind" => "abst", "para" => $_[0]->[1], "body" => $_[0]->[3] } ]
            } 
        );
$varlist = ($wraith::many->($wraith::token->('[A-Za-z_]+'))) ** sub { [ $_[0] ] }; # 9
$appterm = ($wraith::many->(\$aterm)) ** sub { [ $_[0] ] }; # 10
$aterm = ( ($wraith::token->('\(') >> \$term >> $wraith::token->('\)')) **  # 11
            sub { [ { "kind" => "applterm", "body" => $_[0]->[1] } ] } 
         ) |
         ( ($wraith::token->('[A-Za-z_]+')) ** sub { [ { "kind" => "applvar", "val" => $_[0]->[0] } ] } );

sub emitabst;
sub emitappl;
sub emitapplterm;
sub emitapplvar;
sub emitterm;
sub emitdefn;

my %emitmethods = (
    "term" => \&emitterm,
    "defn" => \&emitdefn,
    "appl" => \&emitappl,
    "abst" => \&emitabst,
    "applterm" => \&emitapplterm,
    "applvar" => \&emitapplvar
);

sub emitabst {
    my $abstref = $_[0];
    my $params = $abstref->{"para"};
    my $nparams = @$params;
    my $c_param = shift @$params;
    my $codefrag = undef;
    if ($nparams) {
        $codefrag .= "sub { my \$$c_param = \$_[0]; ";
    } 
    if (@$params) {
        $codefrag .= emitabst($abstref);
    } else {
        $codefrag .= $emitmethods{$abstref->{"body"}->{"kind"}}->($abstref->{"body"});
    }
    $codefrag.' }'
}

sub emitappl {
    my $applref = $_[0];
    my $oplist = $applref->{"body"};
    my $codefrag = undef;
    my $addparen = 0;
    while (@$oplist) {
        my $opitr = shift @$oplist;
        if ($addparen) {
            $codefrag .= '( ';
        }
        $codefrag .= $emitmethods{$opitr->{"kind"}}->($opitr);
        if ($addparen) {
            $codefrag .= ' )';
        }
        if (@$oplist) {
            $codefrag .= '->';
            $addparen = 1;
        }
    }
    $codefrag
}

sub emitapplterm {
    my $atermref = $_[0];
    $emitmethods{$atermref->{"body"}->{"kind"}}->($atermref->{"body"})
}

sub emitapplvar {
    my $varref = $_[0];
    '$'. $varref->{"val"}
}

sub emitterm {
    my $termref = $_[0];
    $emitmethods{$termref->{"body"}->{"kind"}}->($termref->{"body"})
}

sub emitdefn {
    my $defnref = $_[0];
    'my $' . $defnref->{"name"} .' = '. $emitmethods{$defnref->{"body"}->{"kind"}}->($defnref->{"body"}) .';'
}

my $res = $formlist->('true = \x y.x; x x y; Y = \f.(\x y.f (x x)) (\x y. f (x x));');
for my $itr (@{$res->[0]->[0]}) {
    if ($itr->{"kind"} eq "term") {
        push $expr_root{"term"}, $itr;
    } else {
        push $expr_root{"defn"}, $itr;
    }
}
#die;

my ($defnlist, $termlist) = ($rootref->{"defn"}, $rootref->{"term"});

print "# defnlist: \n";
for my $defnitr (@$defnlist) {
    print emitdefn($defnitr); print "\n";
}

print "# termlist: \n";
for my $termitr (@$termlist) {
    print emitterm($termitr); print "\n";
}
