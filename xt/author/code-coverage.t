#!perl
use Test::More tests => 2;
use Devel::Cover::DB;
my $db = new Devel::Cover::DB db => 'cover_db';
$db->merge_runs;
my $cover = $db->cover;
for my $file (sort $cover->items) {
    my $crits = $cover->get($file);
    for my $crit (qw(subroutine statement)) {
        my @vals = $crits->$crit->values;
        my $covered = grep $_, @vals;
        $covered == @vals
        ? pass "\u$crit coverage for $file is $covered/".scalar(@vals)
        : fail "\u$crit coverage for $file is $covered/".scalar(@vals);
    }
}
