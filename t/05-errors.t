#!perl -T
use 5.020;
use warnings;
use Test::More tests => 17;

use Plate;

my $warned;
$SIG{__WARN__} = sub {
    $warned = 1;
    goto &diag;
};

like eval { new Plate invalid => 1 } // $@,
qr"^\QInvalid setting 'invalid' at ", "Can't set invalid settings";

like eval { new Plate cache_path => '/no/such/path/ exists' } // $@,
qr"^Can't create cache directory ", "Can't set invalid cache_path";

like eval { new Plate path => '/no/such/path/ exists' } // $@,
qr"^Can't set path to ", "Can't set invalid path";

like eval { new Plate filters => 'not a hash' } // $@,
qr"^\QInvalid filters (not a hash reference) ", "Can't set invalid filters";

like eval { new Plate globals => ['not a hash'] } // $@,
qr"^\QInvalid globals (not a hash reference) ", "Can't set invalid globals";

my $plate = new Plate;

ok !eval { $plate->define(err => <<'PLATE');
% No opening tag
</%def>
PLATE
}, 'Missing opening %def tag';
like $@, qr"^\QClosing </%def> tag without opening <%def...> tag at err line 2.
Plate compilation failed", 'Expected error';

ok !eval { $plate->define(err => <<'PLATE');
%% No closing tag
<%%def -missing>
PLATE
}, 'Missing closing %def tag';
like $@, qr"^\QOpening <%%def...> tag without closing </%%def> tag at err line 1.
Plate precompilation failed", 'Expected error';

ok !eval { $plate->define(err => <<'PLATE');
<&& .missing &&>
<%%def .missing>
Defined too late
</%%def>
PLATE
}, 'Must declare %def blocks before use';
like $@, qr"^\QCan't read .missing.plate: No such file or directory at err line 1.
Plate precompilation failed", 'Expected error';

$plate->define(err => <<'PLATE');
Defined only in precompilation
<%%def .missing>
</%%def>
<& .missing &>
PLATE
ok !eval { $plate->serve('err') }, "Can't use precompiled %def blocks during runtime";
is $@, "Can't read .missing.plate: No such file or directory at err line 4.\n", 'Expected error';

ok !eval { $plate->define(err => <<'PLATE');
<& bad |filter &>
PLATE
}, 'Invalid filter';
like $@, qr"^No 'filter' filter defined ", 'Expected error';

$plate->define(err => <<'PLATE');
<& err &>
PLATE
is eval { $plate->serve_with(\' ', 'err') } // $@,
qq'Call depth limit exceeded while calling "err" at err line 1.\n', 'Error on deep recursion';

ok !$warned, 'No warnings';
