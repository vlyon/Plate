#!perl -T
use 5.020;
use warnings;
use Test::More tests => 26;

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

like eval { new Plate invalid => 1 } // $@,
qr"^\QInvalid setting 'invalid' at ", "Can't set invalid settings";

like eval { new Plate cache_path => '/no/such/path/ exists' } // $@,
qr"^Can't create cache directory ", "Can't set invalid cache_path";

SKIP: {
    skip 'Test unwriteable cache_path, but / is writeable', 1 if -w '/';

    like eval { new Plate cache_path => '/' } // $@,
    qr"^Cache directory / is not writeable", "Can't set unwriteable cache_path";
}

like eval { new Plate path => '/no/such/path/ exists' } // $@,
qr"^Can't set path to ", "Can't set invalid path";

like eval { new Plate filters => 'not a hash' } // $@,
qr"^\QInvalid filters (not a hash reference) ", "Can't set invalid filters";

like eval { new Plate globals => ['not a hash'] } // $@,
qr"^\QInvalid globals (not a hash reference) ", "Can't set invalid globals";

my $plate = new Plate;

like eval { $plate->filter(-test => 'no::such_sub') } // $@,
qr"^\QInvalid filter name '-test' ", "Can't set invalid filter name";

like eval { $plate->filter(test => 'no::such_sub') } // $@,
qr"^\QInvalid subroutine 'no::such_sub' for filter 'test' ", "Can't set invalid filter sub";

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

ok !eval { $plate->define(err => '<& bad |filter &>') }, 'Invalid filter';
like $@, qr"^No 'filter' filter defined ", 'Expected error';

$plate->define(err => '<& err &>');
is eval { $plate->serve_with(\' ', 'err') } // $@,
qq'Call depth limit exceeded while calling "err" at err line 1.\n', 'Error on deep recursion';

rmdir 't/tmp_dir' or diag "Can't remove t/tmp_dir: $!" if -d 't/tmp_dir';
$plate->set(path => 't', cache_path => 't/tmp_dir', umask => 027);
rmdir 't/tmp_dir' or diag "Can't remove t/tmp_dir: $!";
like eval { $plate->serve('data/faulty') } // $@,
qr"^Can't create cache directory ./t/tmp_dir/data: No such file or directory", 'Error creating cache directory';

$plate->set(path => 't/data');
if (open my $fh, '>', 't/tmp_dir/outer.pl') {
    print $fh '{';
    close $fh;
}
like eval { $plate->serve('outer') } // $@,
qr/^syntax error /m, 'Error parsing cache file';

chmod 0, 't/tmp_dir/outer.pl';
like eval { $plate->serve('outer') } // $@,
qr"^Couldn't load ./t/tmp_dir/outer.pl: ", 'Error reading cache file';
unlink 't/tmp_dir/outer.pl';

rmdir 't/tmp_dir' or diag "Can't remove t/tmp_dir: $!";
like eval { $plate->serve('outer') } // $@,
qr"^Can't write ./t/tmp_dir/outer.pl: No such file or directory", 'Error writing cache file';

$plate->set(path => undef, cache_path => undef);
like eval { $plate->serve('test') } // $@,
qr"^Plate template 'test' does not exist ", 'Error on undefined path & cache_path';

$plate->set(cache_path => 't/tmp_dir', umask => 0777);
like eval { $plate->set(path => 't/tmp_dir') } // $@,
qr"^Can't set path to t/tmp_dir/: Not accessable", 'Error on inaccessable path';
rmdir 't/tmp_dir' or diag "Can't remove t/tmp_dir: $!";

ok !$warned, 'No warnings';
