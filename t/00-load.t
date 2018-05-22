#!perl -T
use 5.020;
use warnings;
use Test::More tests => 1;

use_ok 'Plate' or BAIL_OUT;
diag "Testing Plate $Plate::VERSION, Perl $], $^X";
