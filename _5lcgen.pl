#!/usr/bin/env perl

use Parse::Lex;
use Switch;
use _5lcparse;

my @tokens = (
    qw (
        LPAREN      [\(]
        RPAREN      [\)]
        LAMBDA      [\\\\]
        SEMICOLON   [;]
        VAR         [A-Za-z_]+
        DOT         [\.]
        EQ          [=]
    )
);

my $lexer = Parse::Lex->new(@tokens);
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

my $parser = _5lcparse->new();
$parser->YYParse(yylex => \&lexana);

my $indent = 0;

sub putindent {
    for (my $itr = 0; $itr < $indent; $itr++) {
        print "  ";
    }
}

sub dumpterm {
    my $termref = $_[0];
    putindent; print "expr: \n";
    ($termref->{"body"})
}

sub dumpdefn {
    my $defnref = $_[0];
    putindent; print "defn: ", $defnref->{"name"}, "\n";
    ($defnref->{"body"})
}

sub dumpappl {
    my $applref = $_[0];
    putindent; print "appl: \n";
    my $applbody = $applref->{"body"};
    (@$applbody)
}

sub dumpabst {
    my $abstref = $_[0];
    putindent; print "abst: ";
    my $paramlist = $abstref->{"para"};
    for my $elt (@$paramlist) {
        print $elt, ' ';
    }
    print "\n";
    ($abstref->{"body"})
}

sub dumpaterm {
    my $atermref = $_[0];
    putindent; print "aterm: \n";
    ($atermref->{"body"})
}

sub dumpvar {
    my $varref = $_[0];
    putindent; print "var: ", $varref->{"val"}, "\n";
    ()
}

my %dumpmethods = (
    "term" => \&dumpterm,
    "defn" => \&dumpdefn,
    "appl" => \&dumpappl,
    "abst" => \&dumpabst,
    "applterm" => \&dumpaterm,
    "applvar" => \&dumpvar
);

sub dumpnode {
    $indent++;
    my $node = $_[0];
    my @reslist = $dumpmethods{$node->{"kind"}}->($node);
    for my $resnode (@reslist) {
        dumpnode($resnode);
    }
    $indent--;
}

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

my $rootref = _5lcparse::getrootref;
my ($defnlist, $termlist) = ($rootref->{"defn"}, $rootref->{"term"});

print "# defnlist: \n";
for my $defnitr (@$defnlist) {
    #dumpnode($defnitr);
    print emitdefn($defnitr); print "\n";
}

print "# termlist: \n";
for my $termitr (@$termlist) {
    #dumpnode($termitr);
    print emitterm($termitr); print "\n";
}
