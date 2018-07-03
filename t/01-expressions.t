#!perl -T
use 5.020;
use warnings;
use Test::More tests => 21;

BEGIN {
    if ($ENV{AUTHOR_TESTING}) {
        require Devel::Cover;
        import Devel::Cover -db => 'cover_db', -coverage => qw(branch statement subroutine), -silent => 1, '+ignore' => qr'^t/';
    }
}

use Plate;

my $warned;
$SIG{__WARN__} = sub {
    $warned = 1;
    goto &diag;
};

my $plate = new Plate;

is $plate->serve(\'<% "<html> this & that" |%>'),
'<html> this & that',
'Unfiltered expression';

is $plate->serve(\'<% "<html> this & that" %>'),
'&lt;html&gt; this &amp; that',
'Automatically filtered expression';

is $plate->serve(\'<% "<html> this & that" |html %>'),
'&lt;html&gt; this &amp; that',
'Explicitly filtered expression';

is $plate->serve(\'<% "<html> this & that" | html | html %>'),
'&amp;lt;html&amp;gt; this &amp;amp; that',
'Double filtered expression';

$plate->set(keep_undef => 1);
is $plate->serve(\'<% undef |%>'),
undef,
'Undefined expression is kept';

$plate->set(keep_undef => undef);
is $plate->serve(\'<% undef |html %>'),
'',
'Undefined expression is coerced to ""';

is $plate->serve(\'<% my $i = 7; $i * 3 % 4 | %>'),
'1',
'Complex expression';

is $plate->serve(\'<%join ",",@_|%>', 1..9),
'1,2,3,4,5,6,7,8,9',
'Passed arguments';

is $plate->serve(\"<one>\\\n<two>\n<three>\\\n"),
"<one><two>\n<three>",
'Remove escaped newlines';

$plate->set(vars => {
        '$var' => \'String',
        '@var' => ['Array'],
        '%var' => {a => 'Hash'},
        obj    => \$plate,
        CONST  => 1,
    });
is $plate->serve(\'<% $var %> <% "@var" %> <% $var{a} %> <% ref $obj %> <% CONST %>'),
'String Array Hash Plate 1',
'Set & use vars';

$plate->set(package => 'Some::Where');
is $plate->serve(\'<% $var %> <% $var[0] %> <% $Some::Where::var{a} %> <% Plate::Template::CONST %>'),
'String Array Hash 1',
'Set a new package name & use the same vars';

ok $plate->var(trim => sub { $_[0] =~ s/^\s+|\s+$//gr }), 'Set a local function';
is $plate->serve(\'<% trim "  Hello World\n" %>'),
'Hello World',
'Call a local function';

$plate->var('$var' => undef);
is $plate->serve(\'<% $var %>'),
'',
'Remove a var';

$plate->set(vars => undef);
is $plate->serve(\'<% @var %>'),
'0',
'Remove all vars';

$plate->filter(upper => sub { uc $_[0] });
is $plate->serve(\'<% "Hello World" |upper %>'),
'HELLO WORLD',
'Add a filter by subroutine reference';

sub lower { lc $_[0] };
$plate->filter(lower => 'lower');
is $plate->serve(\'<% "Hello World" |lower %>'),
'hello world',
'Add a filter by subroutine name';

$plate->filter(lower => sub { lcfirst $_[0] });
is $plate->serve(\'<% "Hello World" |lower %>'),
'hello World',
'Replace a filter';

$plate->set(auto_filter => 'upper');
is $plate->serve(\'<% "Hello World" %>'),
'HELLO WORLD',
'Set a default filter';

$plate->set(auto_filter => undef);
is $plate->serve(\'<% "Hello World" %>'),
'Hello World',
'Remove auto_filter';

ok !$warned, 'No warnings';
