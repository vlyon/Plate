#!perl -T
use 5.020;
use warnings;
use Test::More tests => 18;

use Plate;

my $warned;
$SIG{__WARN__} = sub {
    $warned = 1;
    goto &diag;
};

my $plate = Plate->new;

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

ok $plate->global(hello => 'Hello'), 'Set a global scalar';
is $plate->serve(\"% \$hello .= ' World';\n<% \$hello %>"),
'Hello World',
'Use a global scalar';

ok $plate->global(trim => sub { $_[0] =~ s/^\s+|\s+$//gr }), 'Set a global function';
is $plate->serve(\'<% trim "  Hello World\n" %>'),
'Hello World',
'Call a global function';

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

ok !$warned, 'No warnings';
