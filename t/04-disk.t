#!perl -T
use 5.020;
use warnings;
use Test::More tests => 28;

BEGIN {
    if ($ENV{AUTHOR_TESTING}) {
        require Devel::Cover;
        import Devel::Cover -db => 'cover_db', -coverage => qw(statement subroutine), -silent => 1, '+ignore' => qr'^t/';
    }
}

my $warned;
$SIG{__WARN__} = sub {
    $warned = 1;
    goto &diag;
};
sub warnings_are(&$;$) {
    my($sub, $exp, $out) = @_;
    my @got;
    local $SIG{__WARN__} = sub {
        push @got, join '', @_;
    };
    $sub->();
    my $ok = @got == @$exp;
    $ok &&= $got[$_] eq $$exp[$_] for 0..$#got;
    ok $ok, $out
        or do {
        diag "found warning: $_" for @got;
        diag "found no warnings" unless @got;
        diag "expected warning: $_" for @$exp;
        diag "expected no warnings" unless @$exp;
    };
}

use Plate;

sub temp_files {qw(t/data/faulty.pl t/data/inner.pl t/data/outer.pl t/data/test.pl t/data/utf8.pl t/data/tmp.plate)}

use utf8;
binmode Test::More->builder->failure_output, ':utf8';

unlink $_ for temp_files;
END { unlink $_ for temp_files }

my $output = <<'OUTPUT';
[
$var = "Tom, Dick &amp; Harry"
Some <inner args="this &amp; that">between</inner> line.
]
this & that
this &amp; that
this &amp;amp; that
OUTPUT

my $plate = new Plate path => 't/data', cache_path => 't/data';

ok $plate->does_exist('test'), "Plate 'test' does exist";
ok $plate->can_serve('test'), "Plate 'test' can be served";

ok !$plate->does_exist('missing'), "Plate 'missing' doesn't exist";
ok !$plate->can_serve('missing'), "Plate 'missing' can't be served";

ok $plate->does_exist('faulty'), "Plate 'faulty' does exist";
ok !$plate->can_serve('faulty'), "Plate 'faulty' can't be served";
like $@, qr/^Bareword "oops" not allowed .*^Plate compilation failed /ms, 'Expected compilation error';

$plate->define(defined => 'defined');
ok $plate->does_exist('defined'), "Defined plate does exist";
ok $plate->can_serve('defined'), "Defined plate can be served";

$plate->undefine('defined');
ok !$plate->does_exist('defined'), "Undefined plate doesn't exist";
ok !$plate->can_serve('defined'), "Undefined plate can't be served";

warnings_are {
    is $plate->serve('test', qw(this & that)), $output, 'Expected ouput';
} [
    "inner-2-warn at t/data/inner.plate line 2.\n",
    "test-6-warn at t/data/test.plate line 6.\n",
], 'Expected warnings';

ok -f 't/data/inner.pl' && -f 't/data/outer.pl' && -f 't/data/test.pl', 'Cache files created';

$plate->undefine;

warnings_are {
    is $plate->serve('test', qw(this & that)), $output, 'Same output from cache';
} [
    "inner-2-warn at t/data/inner.plate line 2.\n",
    "test-6-warn at t/data/test.plate line 6.\n",
], 'Same warnings from cache';

# Touch t/data/test.plate
utime undef, undef, 't/data/test.plate';

warnings_are {
    is $plate->serve('test', qw(this & that)), $output, 'Same output';
} [
    "inner-2-warn at t/data/inner.plate line 2.\n",
    "test-6-warn at t/data/test.plate line 6.\n",
], 'Same warnings';

isnt +(stat 't/data/test.pl')[9], 946684800, 'Cache was updated';

is $plate->serve('utf8'),
'ῌȇɭɭо Ẇöŗld‼',
'Render as UTF-8';

$plate = new Plate path => 't/data', encoding => 'latin1';
is $plate->serve('utf8'),
"á¿\214È\207É­É­Ð¾ áº\206Ã¶Å\227ldâ\200¼",
'Render as Latin-1';

$plate = new Plate path => 't/data', io_layers => ':raw';
is $plate->serve('utf8'),
"á¿\214È\207É­É­Ð¾ áº\206Ã¶Å\227ldâ\200¼",
'Render as binary';

$plate = new Plate path => 't/data', cache_code => 1, static => 1;

if (open my $fh, '>', 't/data/tmp.plate') {
    print $fh 'abc';
    close $fh;
}

is $plate->serve('tmp'),
'abc',
'Serve plate cached in memory';

unlink 't/data/tmp.plate';

is $plate->serve('tmp'),
'abc',
'Serve plate from memory cache without modification check';

$plate = new Plate path => 't/data', cache_code => 1, static => 0;

my $mod = time - 1;
if (open my $fh, '>', 't/data/tmp.plate') {
    print $fh 'abc';
    close $fh;
    utime $mod, $mod, 't/data/tmp.plate';
}
$plate->can_serve('tmp'); # Cache in memory
if (open my $fh, '>', 't/data/tmp.plate') {
    print $fh 'xyz';
    close $fh;
    utime $mod, $mod, 't/data/tmp.plate';
}
is $plate->serve('tmp'),
'abc',
'Serve plate from memory cache with modification check';

utime undef, undef, 't/data/tmp.plate';
is $plate->serve('tmp'),
'xyz',
'Serve reloaded plate';

unlink 't/data/tmp.plate';
ok !eval { $plate->serve('tmp') }, "Don't serve deleted plate";

ok !$warned, 'No unexpected warnings';
