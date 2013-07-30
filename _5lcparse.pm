####################################################################
#
#    This file was generated using Parse::Yapp version 1.05.
#
#        Don't edit this file, use source file instead.
#
#             ANY CHANGE MADE HERE WILL BE LOST !
#
####################################################################
package _5lcparse;
use vars qw ( @ISA );
use strict;

@ISA= qw ( Parse::Yapp::Driver );
use Parse::Yapp::Driver;

#line 1 "_5lcparse.yp"

    my %expr_root = ( "kind" => "list", "defn" => [], "term" => [] );
    sub getrootref { \%expr_root }


sub new {
        my($class)=shift;
        ref($class)
    and $class=ref($class);

    my($self)=$class->SUPER::new( yyversion => '1.05',
                                  yystates =>
[
	{#State 0
		ACTIONS => {
			'VAR' => 1,
			'LAMBDA' => 7,
			'LPAREN' => 9,
			'SEMICOLON' => -10
		},
		DEFAULT => -2,
		GOTOS => {
			'form' => 2,
			'formlist' => 3,
			'term' => 8,
			'list' => 4,
			'appterm' => 5,
			'aterm' => 6
		}
	},
	{#State 1
		ACTIONS => {
			'EQ' => 10
		},
		DEFAULT => -13
	},
	{#State 2
		ACTIONS => {
			'LPAREN' => 9,
			'SEMICOLON' => -10,
			'VAR' => 1,
			'LAMBDA' => 7
		},
		DEFAULT => -2,
		GOTOS => {
			'form' => 2,
			'formlist' => 11,
			'term' => 8,
			'appterm' => 5,
			'aterm' => 6
		}
	},
	{#State 3
		DEFAULT => -1
	},
	{#State 4
		ACTIONS => {
			'' => 12
		}
	},
	{#State 5
		DEFAULT => -6
	},
	{#State 6
		ACTIONS => {
			'VAR' => 13,
			'LPAREN' => 9
		},
		DEFAULT => -10,
		GOTOS => {
			'appterm' => 14,
			'aterm' => 6
		}
	},
	{#State 7
		ACTIONS => {
			'VAR' => 16
		},
		DEFAULT => -8,
		GOTOS => {
			'varlist' => 15
		}
	},
	{#State 8
		ACTIONS => {
			'SEMICOLON' => 17
		}
	},
	{#State 9
		ACTIONS => {
			'LAMBDA' => 7,
			'VAR' => 13,
			'LPAREN' => 9
		},
		DEFAULT => -10,
		GOTOS => {
			'appterm' => 5,
			'aterm' => 6,
			'term' => 18
		}
	},
	{#State 10
		ACTIONS => {
			'LPAREN' => 9,
			'LAMBDA' => 7,
			'VAR' => 13
		},
		DEFAULT => -10,
		GOTOS => {
			'term' => 19,
			'aterm' => 6,
			'appterm' => 5
		}
	},
	{#State 11
		DEFAULT => -3
	},
	{#State 12
		DEFAULT => 0
	},
	{#State 13
		DEFAULT => -13
	},
	{#State 14
		DEFAULT => -11
	},
	{#State 15
		ACTIONS => {
			'DOT' => 20
		}
	},
	{#State 16
		ACTIONS => {
			'VAR' => 16
		},
		DEFAULT => -8,
		GOTOS => {
			'varlist' => 21
		}
	},
	{#State 17
		DEFAULT => -4
	},
	{#State 18
		ACTIONS => {
			'RPAREN' => 22
		}
	},
	{#State 19
		ACTIONS => {
			'SEMICOLON' => 23
		}
	},
	{#State 20
		ACTIONS => {
			'VAR' => 13,
			'LAMBDA' => 7,
			'LPAREN' => 9
		},
		DEFAULT => -10,
		GOTOS => {
			'term' => 24,
			'aterm' => 6,
			'appterm' => 5
		}
	},
	{#State 21
		DEFAULT => -9
	},
	{#State 22
		DEFAULT => -12
	},
	{#State 23
		DEFAULT => -5
	},
	{#State 24
		DEFAULT => -7
	}
],
                                  yyrules  =>
[
	[#Rule 0
		 '$start', 2, undef
	],
	[#Rule 1
		 'list', 1, undef
	],
	[#Rule 2
		 'formlist', 0, undef
	],
	[#Rule 3
		 'formlist', 2, undef
	],
	[#Rule 4
		 'form', 2,
sub
#line 23 "_5lcparse.yp"
{ my $term = { "kind" => "term", "body" => $_[1] }; push $expr_root{"term"}, $term; $term }
	],
	[#Rule 5
		 'form', 4,
sub
#line 24 "_5lcparse.yp"
{ my $defn = { "kind" => "defn", "name" => $_[1], "body" => $_[3] }; push $expr_root{"defn"}, $defn; $defn }
	],
	[#Rule 6
		 'term', 1,
sub
#line 27 "_5lcparse.yp"
{ my $term = { "kind" => "appl", "body" => $_[1] }; $term }
	],
	[#Rule 7
		 'term', 4,
sub
#line 28 "_5lcparse.yp"
{ my $term = { "kind" => "abst", "para" => $_[2], "body" => $_[4] }; $term }
	],
	[#Rule 8
		 'varlist', 0,
sub
#line 31 "_5lcparse.yp"
{ [] }
	],
	[#Rule 9
		 'varlist', 2,
sub
#line 32 "_5lcparse.yp"
{ my $sublist = $_[2]; my @list = ( $_[1], @$sublist ); \@list }
	],
	[#Rule 10
		 'appterm', 0,
sub
#line 35 "_5lcparse.yp"
{ [] }
	],
	[#Rule 11
		 'appterm', 2,
sub
#line 36 "_5lcparse.yp"
{ my $sublist = $_[2]; my @list = ( $_[1], @$sublist ); \@list }
	],
	[#Rule 12
		 'aterm', 3,
sub
#line 39 "_5lcparse.yp"
{ my $term = { "kind" => "applterm", "body" => $_[2] }; $term }
	],
	[#Rule 13
		 'aterm', 1,
sub
#line 40 "_5lcparse.yp"
{ my $term = { "kind" => "applvar", "val" => $_[1] }; $term }
	]
],
                                  @_);
    bless($self,$class);
}

#line 43 "_5lcparse.yp"


1;
