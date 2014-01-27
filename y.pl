#!/usr/bin/env perl

sub Ycbv {
    my $f = shift;
    sub {
        my $x = shift;
        $f->( sub { my $y = shift; $x->($x)->($y) } )
    }->(
        sub {
            my $x = shift;
            $f->( sub { my $y = shift; $x->($x)->($y) } )
        }
    )
}

sub facbody {
    my $f = shift;
    sub {
        my $x = shift;
        ($x) ? ($x * $f->($x - 1)) : (1)
    }
}

my $fac = Ycbv(\&facbody);
print $fac->(6), "\n";
