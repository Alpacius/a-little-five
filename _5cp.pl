#!/usr/bin/env perl

use strict;
use Scalar::Defer;

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
            #print "x=$x, xs=$xs\n";
            if ($p->($x)) {
                #print "success $x\n";
                return $succeed->($x)->($xs);
            } else {
                #print "fail $x\n";
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

our $alt = 
sub {
    my ($p1, $p2) = @_;
    sub {
        my $inp = $_[0];
        $concat->($p1->($inp), $p2->($inp))
    }
};

our $then = 
sub {
    my ($p1, $p2) = @_;
    sub {
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
    my ($p, $f) = @_;
    sub {
        my $inp = $_[0];
        my $reslist = $p->($inp);
        #print "using: ".@$reslist." results\n";
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

sub expn;
sub term;
sub factor;
sub number;

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
    [ $l->[0] / $l->[2] ]
}

my ($expn, $term, $factor);

$expn = 
defer {
    $alt->(
        $using->($then->($term, $then->($literal->('+'), $term)), \&do_add),
        $alt->(
            $using->($then->($term, $then->($literal->('-'), $term)), \&do_sub),
            $term
        )
    )
};

$term =
defer {
    $alt->(
        $using->($then->($factor, $then->($literal->('*'), $factor)), \&do_mul),
        $alt->(
            $using->($then->($factor, $then->($literal->('/'), $factor)), \&do_div),
            $factor
        )
    )
};

$factor =
defer {
    $alt->(
        $using->(number(), sub { my $l = $_[0]; my $val = undef; for my $i (@$l) { $val .= $i; } [ $val ] } ),
        $using->($then->($literal->('('), $then->($expn, $literal->(')'))), sub { my $l = $_[0]; [ $l->[1] ] } )
    )
};

$expn = force $expn;
$term = force $term;
$factor = force $factor;

sub number {
    #print "number\n";
    $many->(
        $alt->($literal->('0'), 
               $alt->($literal->('1'),
                      $alt->($literal->('2'),
                             $alt->($literal->('3'),
                                    $alt->($literal->('4'),
                                           $alt->($literal->('5'),
                                                  $alt->($literal->('6'),
                                                         $alt->($literal->('7'),
                                                                $alt->($literal->('8'),
                                                                       $literal->('9')
                                                                      )
                                                               )
                                                        )
                                                 )
                                          )
                                   )
                            )
                     )
              )
    )
}

# a simple test
print $expn->('(2+(4-1)*3)+1')->[0]->[0]->[0], "\n";
