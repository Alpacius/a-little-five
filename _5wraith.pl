#!/usr/bin/env perl

use strict;

sub descalar {
    if (ref($_[0]) eq "REF") {
        return ${$_[0]};
    } else {
        return $_[0];
    }
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
sub {
    my $v = $_[0];
    sub {
        my $u = (ref($v) eq "ARRAY") ? $v : [ $v ];
        [ [ $u, $_[0] ] ]
    }
};

our $fail = 
sub {
    []
};

our $satisfy = 
sub {
    my $p = $_[0];
    sub {
        if (my ($x, $xs) = ($_[0] =~ /(.)(.*)/s) ) {
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
sub {
    my $y = $_[0];
    $satisfy->( 
        sub { 
            #print "literal $y against $_[0] - "; 
            $y eq $_[0] 
        } 
    )
};

our $literals = 
sub {
    my $y = $_[0];
    $satisfy->(
        sub {
            index($y, $_[0]) != -1
        }
    )
};

our $alt = 
sub {
    my ($p1_, $p2_) = @_;
    sub {
        my ($p1, $p2) = (descalar($p1_), descalar($p2_));
        my $inp = $_[0];
        $concat->($p1->($inp), $p2->($inp))
    }
};

our $then = 
sub {
    my ($p1_, $p2_) = @_;
    sub {
        my ($p1, $p2) = (descalar($p1_), descalar($p2_));
        my $inp = $_[0];
        my $reslist1 = $p1->($inp);
        my $finlist = [];
        for my $respair (@$reslist1) {
            my ($v1, $reslist2) = ( $respair->[0], $p2->($respair->[1]) );
            for my $finpair (@$reslist2) {
                my $val1 = (ref($v1) eq "ARRAY") ? $v1 : [ $v1 ];
                my $val2 = (ref($finpair->[0]) eq "ARRAY") ? $finpair->[0] : [ $finpair->[0] ];
                push @$finlist, [ $concat->($val1, $val2), $finpair->[1] ];
            }
        }
        $finlist
    }
};

# XXX wow 'tis ugly
# XXX This combinator is only used by many. You know what to do.
my $then_lazy =
sub {
    my ($p1, $p2) = @_;
    sub {
        my $inp = $_[0];
        my $reslist1 = $p1->($inp);
        my $finlist = [];
        for my $respair (@$reslist1) {
            my ($v1, $reslist2) = ( $respair->[0], $p2->()->($respair->[1]) );
            for my $finpair (@$reslist2) {
                my $val1 = (ref($v1) eq "ARRAY") ? $v1 : [ $v1 ];
                my $val2 = (ref($finpair->[0]) eq "ARRAY") ? $finpair->[0] : [ $finpair->[0] ];
                push @$finlist, [ $concat->($val1, $val2), $finpair->[1] ];
            }
        }
        $finlist
    }
};

our $using =
sub {
    my ($p_, $f) = @_;
    sub {
        my $p = descalar($p_);
        my $inp = $_[0];
        my $reslist = $p->($inp);
        my $finlist = [];
        for my $respair (@$reslist) {
            push @$finlist, [ $f->($respair->[0]), $respair->[1] ];
        }
        $finlist
    }
};

sub many_s {
    my $p = $_[0];
    $alt->($then_lazy->($p, sub { many_s($p) }), $succeed->( [] ))
}
our $many = \&many_s;

sub do_add {
    my $l = $_[0];
    [ $l->[0] + $l->[2] ]
}

sub do_sub {
    my $l = $_[0];
    [ $l->[0] - $l->[2] ]
}

sub do_mul {
    my $l = $_[0];
    [ $l->[0] * $l->[2] ]
}

sub do_div {
    my $l = $_[0];
    # XXX Beware of bad matching
    if ($l->[2] == 0) {
        $l->[2] = 1;
    }
    [ $l->[0] / $l->[2] ]
}

my ($expn, $term, $factor);

$expn = 
    $alt->(
        $using->($then->(\$term, $then->($literal->('+'), \$expn)), \&do_add),
        $alt->(
            $using->($then->(\$term, $then->($literal->('-'), \$expn)), \&do_sub),
            \$term
        )
    );

$term =
    $alt->(
        $using->($then->(\$factor, $then->($literal->('*'), \$term)), \&do_mul),
        $alt->(
            $using->($then->(\$factor, $then->($literal->('/'), \$term)), \&do_div),
            \$factor
        )
    );

$factor =
    $alt->(
        $using->(number(), sub { my $l = $_[0]; my $val = undef; for my $i (@$l) { $val .= $i; } [ $val ] } ),
        $using->($then->($literal->('('), $then->(\$expn, $literal->(')'))), sub { my $l = $_[0]; [ $l->[1] ] } )
    );


sub number {
    $many->($literals->('0123456789'))
}

# simple tests
print $expn->('2+(4-1)*3+4-2')->[0]->[0]->[0], "\n";
print $expn->('1+2+3-2*7/2')->[0]->[0]->[0], "\n";
