#!/usr/bin/env perl

sub Y {
    my $f = shift;
    sub {
        my $x = shift;
        $f->(Y($f))->($x)
    }
}

sub facbody {
    my $f = shift;
    sub {
        my $x = shift;
        ($x) ? ($x * $f->($x - 1)) : (1)
    }
}

my $fac = Y(\&facbody);
print $fac->(5), "\n";
