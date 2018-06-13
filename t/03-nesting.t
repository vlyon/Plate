#!perl -T
use 5.020;
use warnings;
use Test::More tests => 13;

BEGIN {
    if ($ENV{AUTHOR_TESTING}) {
        require Devel::Cover;
        import Devel::Cover -db => 'cover_db', -coverage => qw(statement subroutine), -silent => 1, '+ignore' => qr'^t/';
    }
}

use Plate;

my $warned;
$SIG{__WARN__} = sub {
    $warned = 1;
    goto &diag;
};

my $plate = new Plate;

my $sub = $plate->define(test => 'Test');
is ref $sub, 'CODE', 'Plate::define returns a subroutine';
is $plate->serve('test'), 'Test', 'Render a defined plate by name';
is $plate->serve(\'<& test &>'), 'Test', 'Call a defined plate by name';
isnt $plate->define(test => sub { 'Redefined' }), $sub, 'Redefine a plate';
is $plate->serve('test'), 'Redefined', 'Render the redefined plate';

$plate->define(test => '<test @_="<% "@_" %>"><& _ &></test>');
is $plate->serve(\'<&| test, 1..3 &>Content</&>'),
'<test @_="1 2 3">Content</test>',
'Render a plate with content using <& _ &>';

is $plate->serve(\<<'PLATE', 'this', '&', 'that'),
% my $var = "@_";
<&| test, qw(test args) &><inner @_="<% "@_" %>"><% $var %></inner></&>\
PLATE
'<test @_="test args"><inner @_="test args">this &amp; that</inner></test>',
'Render a plate with lexical content';

$plate->define(test => '<test><% &content %></test>');
is $plate->serve(\<<'PLATE', 'this', '&', 'that'),
<&| test, @_ &><inner><% "@_" %></inner></&>\
PLATE
'<test>&lt;inner&gt;this &amp;amp; that&lt;/inner&gt;</test>',
'Render a plate with content using &content';

is $plate->serve(\'<& test &>'),
'<test></test>',
'Render a plate without content using &content';

$plate->define(a => '<a><&| b, @_ &>x</&></a>');
$plate->define(b => '<b><&| c, @_ &>+<% &content %>+</&></b>');
$plate->define(c => '<c><& _ &> <& _ &></c>');
is $plate->serve('a'), '<a><b><c>+x+ +x+</c></b></a>', 'Multi-level nesting';

$plate->define(a => '<a><&| b, @_ &><% chr 64 + $_[0] %></&></a>');
$plate->define(b => '<b><&| c, @_ &>{<& _ &>"<% shift %>"<% &content %>}</&></b>');
$plate->define(c => <<'PLATE');
<c>
% for (1..3) {
[<& _ &>"<% shift %>"<% &content %>]
% }
</c>\
PLATE
is $plate->serve('a', 1..10),
qq'<a><b><c>\n[{A"1"B}"2"{C&quot;3&quot;D}]\n[{D"4"E}"5"{F&quot;6&quot;G}]\n[{G"7"H}"8"{I&quot;9&quot;J}]\n</c></b></a>',
'Multi-level nested content has access to @_';

$plate->define(a => '<a><&| b &><& c &></&><& c &></a>');
$plate->define(b => '<b><& _ &></b>');
$plate->define(c => <<'PLATE');
<%def b>
inline 1\
</%def>
<c><& b &></c>\
<%def b>
inline 2\
</%def>
<c><& b &></c>\
PLATE
is $plate->serve('a'),
'<a><b><c>inline 1</c><c>inline 2</c></b><c>inline 1</c><c>inline 2</c></a>',
'Inline %def blocks override locally';

ok !$warned, 'No warnings';
