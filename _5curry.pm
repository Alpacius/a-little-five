package _5curry; 

use B qw(svref_2object);

BEGIN {
    require Exporter;
    our $VERSION = 0.1;
    our @ISA = qw(Exporter);
    our @EXPORT = qw(makecurry);
}

sub curry {
    my $f = shift;
    my $args = \@_;
    sub { $f->(@$args, @_) }
}

sub makecurry {
    no strict 'refs';
    my $f = shift;
    my $cv = svref_2object($f);
    my $rawname = $cv->GV->NAME;
    my ($fname, $pkg) = ($rawname .'_5c', caller);
    my $success = 1;
    if (*{$pkg."::$fname"}{CODE}) {
        $success = 0;
    } else {
        *{$pkg."::$fname"} = curry(\&curry, $f);
    }
    $success
}

1
