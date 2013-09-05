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
        my ($p) = deref($_[0]);
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

# test case: a simple expression calculator

my ($expn, $term, $factor, $num);
wraith_rule->makerules(\$expn, \$term, \$factor, \$num);

$expn = ( (\$term >> $wraith::token->('\+') >> \$expn) ** sub { [ $_[0]->[0] + $_[0]->[2] ] } ) |
        ( (\$term >> $wraith::token->('-') >> \$expn) ** sub { [ $_[0]->[0] - $_[0]->[2] ] } ) |
        ( \$term );

$term = ( (\$factor >> $wraith::token->('\*') >> \$term) ** sub { [ $_[0]->[0] * $_[0]->[2] ] } ) |
        ( (\$factor >> $wraith::token->('\/') >> \$term) ** 
            sub { $_[0]->[2] ? [ $_[0]->[0] / $_[0]->[2] ] : [] } ) |
        ( \$factor );

$factor = ( (\$num) ** sub { my $l = $_[0]; my $val = undef; for my $i (@$l) { $val .= $i; } [ $val ] } ) |
          ( ( $wraith::token->('\(') >> \$expn >> $wraith::token->('\)') ) ** sub { my $l = $_[0]; [ $l->[1] ] } );

# both defns are available

$num = $wraith::token->('[1-9][0-9]*');
#$num = $wraith::literals->('123456789') >> $wraith::many->($wraith::literals->('0123456789'));

print $expn->('2 +  (4 - 1) * 3 +  4 -2')->[0]->[0]->[0], "\n";
print $expn->('1+2+3-2*7/ 2')->[0]->[0]->[0], "\n";
