use 5.020;
use warnings;
package Plate 0.1;

use Carp 'croak';
use File::Spec;
use Scalar::Util;
use XSLoader;

use constant WINDOWS => $^O eq 'MSWin32';

BEGIN {
    XSLoader::load __PACKAGE__, $Plate::VERSION;
}

=head1 NAME

Plate - Fast templating engine with support for embedded Perl

=head1 SYNOPSIS

    use Plate;
    
    my $plate = Plate->new(
        path        => '/path/to/plate/files/',
        cache_path  => '/tmp/cache/',
        auto_filter => 'trim',
    );
    
    $plate->filter(html => \&HTML::Escape::escape_html);
    $plate->filter(trim => sub { $_[0] =~ s/^\s+|\s+$//gr });
    
    # Render /path/to/plate/files/hello.plate cached as /tmp/cache/hello.pl
    my $output = $plate->serve('hello');
    print $output;

=cut

my $re_pre = qr'(.*?)(?:
    ^%%\h*(\V*?)\h*(?:\R|\z)|
    ^<%%(perl)>(?:\R|\z)(?:(.*?)^</%%\g-2>(?:\R|\z))?|
    ^<%%def\h+([\w/\.-]+)>(?:\R|\z)|
    <%%\h*(.+?)\h*(?:\|\h*(|\w+(?:\h*\|\h*\w+)*)\h*)?%%>|
    <&&(\|)?\h*(.+?)\h*(?:\|\h*(|\w+(?:\h*\|\h*\w+)*)\h*)?&&>|
    </(%%def|%%perl)>(?:\R|\z)|
    </(&&)>|\z
)'mosx;
my $re_run = qr'(.*?)(?:
    ^%\h*(\V*?)\h*(?:\R|\z)|
    ^<%(perl)>(?:\R|\z)(?:(.*?)^</%\g-2>(?:\R|\z))?|
    ^<%def\h+([\w/\.-]+)>(?:\R|\z)|
    <%\h*(.+?)\h*(?:\|\h*(|\w+(?:\h*\|\h*\w+)*)\h*)?%>|
    <&(\|)?\h*(.+?)\h*(?:\|\h*(|\w+(?:\h*\|\h*\w+)*)\h*)?&>|
    </(%def|%perl)>(?:\R|\z)|
    </(&)>|\z
)'mosx;

sub _parse_text {
    my $text = $_[0];
    $_[2] = $text =~ s/\\\R//g if $_[1] == $re_run;
    $text =~ s/(\\|')/\\$1/g;
    length $text ? "'$text'" : ();
}
sub _parse_cmnt {
    my $cmnt = $_[0];
    $cmnt =~ /^#(?:\s*line\s+(\d+)\s*(?:\s("?)([^"]+)\g2)?\s*|.*)$/
    ? defined $1
        ? defined $3
            ? "\n#line $1 $3"
            : "\n#line $1"
        : ''
    : $cmnt;
}
sub _parse_defn {
    my $defn = $_[0];
    $defn =~ /\W/ ? "'".($defn =~ s/(\\|')/\\$1/gr)."'" : $defn;
}
sub _parse_fltr {
    my $expr = $_[0];
    $expr .= "//''" unless $$Plate::_s{keep_undef};
    if (length $_[1]) {
        for (split /\s*\|\s*/, $_[1]) {
            exists $$Plate::_s{filters}{$_} or croak "No '$_' filter defined";
            $expr = "Plate::_f($_=>$expr)";
        }
    } elsif (not $$Plate::_s{keep_undef}) {
        $expr = "($expr)";
    }
    $expr;
}
sub _parse {
    my @expr;
    my $stmt;
    my $fix_line_num;
    my $expr2stmt = sub {
        if (@expr) {
            if (defined $stmt) {
                $stmt .= '$Plate::_b.=';
            } else {
                $stmt = 'local$Plate::_b=';
            }
            $stmt .= join('.', $_[1] ? splice @expr, 0, $fix_line_num : splice @expr).';';
        } else {
            $stmt //= q"local$Plate::_b='';";
        }
        undef $fix_line_num unless $_[1];
    };
    while ($_[0] =~ /$_[1]/g) {

        if (length $1) {
            push @expr, _parse_text $1, $_[1], my $add_lines;
            (@expr ? $expr[-1] : defined $stmt ? $stmt : ($expr[0] = "''")) .= "\n" x $add_lines if $add_lines;
            $fix_line_num = @expr if $fix_line_num;
        }

        if ($_[1] == $re_run and @Plate::_l and $Plate::_l[0] <= $+[1]) {
            my($pos, $line) = splice @Plate::_l, 0, 2;
            ($pos, $line) = splice @Plate::_l, 0, 2 while @Plate::_l and $Plate::_l[0] <= $+[1];
            my $rem = $+[1] - $pos;
            $line += substr($_[0], $pos, $rem) =~ tr/\n// if $rem;
            $expr2stmt->($_[1]);
            $stmt .= "\n#line $line\n";
        }

        if (defined $2) {
            # % ...
            $expr2stmt->($_[1]);
            $stmt .= _parse_cmnt $2;
            $stmt .= "\n";

        } elsif (defined $3) {
            # <%perl>
            $expr2stmt->($_[1]);
            unless (defined $4) {
                my $line = 1 + $stmt =~ y/\n//;
                $line = "$_[2] line $line.\nPlate ".($_[1] == $re_pre && 'pre').'compilation failed';
                my $tag = ($_[1] == $re_pre && '%').'%'.$3;
                croak "Opening <$tag...> tag without closing </$tag> tag at $line";
            }
            $stmt .= "\n$4\n";

        } elsif (defined $5) {
            # <%def ...>
            $expr2stmt->($_[1]);
            local $_[3] = ($_[1] == $re_pre && '%').'%def';
            $stmt .= 'local$$Plate::_s{mem}{'._parse_defn($5)."}=\nsub{".&_parse.'};';

        } elsif (defined $6) {
            # <% ... %>
            $expr2stmt->($_[1], 1) if $fix_line_num;
            $fix_line_num = push @expr,
            _parse_fltr "do{$6}", $7 // $$Plate::_s{auto_filter};

        } elsif (defined $9) {
            # <& ... &> or <&| ... &>
            my($tmpl, $args) = do { $9 =~ /^([\w\/\.-]+)\s*(?:,\s*(.*))?$/ };
            $expr2stmt->($_[1], 1) if $fix_line_num;
            if (defined $tmpl) {
                if ($tmpl eq '_') {
                    $fix_line_num = push @expr, _parse_fltr defined $8
                    ? do {
                        $args = defined $args ? "($args)" : '';
                        local $_[3] = $_[1] == $re_pre ? '&&' : '&';
                        '(@Plate::_c?do{local@Plate::_c=@Plate::_c;&{splice@Plate::_c,-1,1,sub{'.&_parse."}}$args}:undef)"
                    }
                    : defined $args ? "Plate::content($args)" : '&Plate::content', $10;
                    next;
                }
                $tmpl = defined $args ? "Plate::_r('$tmpl',($args)," : "Plate::_r('$tmpl',";
            } else {
                $tmpl = "Plate::_r($9,";
            }
            $fix_line_num = push @expr,
            _parse_fltr $tmpl.(defined $8 ? (local $_[3] = $_[1] == $re_pre ? '&&' : '&', 'sub{'.&_parse.'}') : 'undef').')', $10;

        } else {
            # </%...> or </&> or \z
            my $tag = $11 // $12 // '';
            if ($tag ne $_[3]) {
                my $line = 1 + join('', $stmt // '', @expr) =~ y/\n//;
                $line = "$_[2] line $line.\nPlate ".($_[1] == $re_pre && 'pre').'compilation failed';
                croak $tag
                ? "Closing </$tag> tag without opening <$tag...> tag at $line"
                : "Opening <$_[3]...> tag without closing </$_[3]> tag at $line";
            }

            my $pl = defined $stmt
            ? $stmt.join('.', '$Plate::_b', @expr)
            : @expr ? join('.', @expr) : "''";
            $pl .= '=~s/\R\z//r' if $_[1] == $re_run and $$Plate::_s{chomp};
            $pl .= "\n" if defined $11;
            return $pl;
        }

        if ($_[1] == $re_pre) {
            $expr2stmt->($_[1]);
            $stmt .= 'push@Plate::_l,length$Plate::_b,__LINE__;';

        } elsif (@Plate::_l and $Plate::_l[0] <= $+[0]) {
            my($pos, $line) = splice @Plate::_l, 0, 2;
            ($pos, $line) = splice @Plate::_l, 0, 2 while @Plate::_l and $Plate::_l[0] <= $+[0];
            my $rem = $+[0] - $pos;
            $line += substr($_[0], $pos, $rem) =~ tr/\n// if $rem;
            $expr2stmt->($_[1]);
            $stmt .= "\n#line $line\n";
        }
    }
}

sub _read {
    open my $fh, '<'.$_[0]{io_layers}, $_[1]
        or croak "Can't read $_[1]: $!";
    local $/;
    scalar <$fh>;
}
sub _write {
    my $umask = umask $$Plate::_s{umask};
    (open(my $fh, '>:utf8', $_[0]), umask $umask)[0]
        or croak "Can't write $_[0]: $!";
    print $fh $_[1];
}
sub _eval {
    eval "package $$Plate::_s{package};$_[0]";
}
sub _compile {
    my($pl, $file) = @_;
    my($line, $sub);
    if (length $file) {
        $line = "\n#line 1 $_[1]\n";
    } else {
        $file = '-';
        $line = '';
    }
    local @Plate::_l;
    # Precompile
    $pl = _parse $pl, $re_pre, $file, '';
    $pl = "sub{$line$pl}";
    $sub = _eval $pl
        or croak $@.'Plate precompilation failed';
    defined($pl = eval { $sub->() })
        or croak $@.'Plate precompilation failed';
    # Compile
    $pl = _parse $pl, $re_run, $file, '';
    $pl = "$$Plate::_s{once}sub{$$Plate::_s{init}$line$pl}";
    $sub = _eval $pl
        or croak $@.'Plate compilation failed';
    # Cache
    _write $_[2], "use 5.020;use warnings;use utf8;package $$Plate::_s{package};$pl" if defined $_[2];
    $$Plate::_s{mod}{$_[3]} = $_[4] if defined $_[4];
    return $sub;
}
sub _make_cache_dir {
    my($dir, @mkdir) = $_[1];
    unshift @mkdir, $_[0]{cache_path}.$dir until $dir !~ s|/[^/]*$|| or -d $_[0]{cache_path}.$dir;
    return unless @mkdir;
    my $umask = umask $_[0]{umask};
    mkdir $_ or umask $umask, croak "Can't create cache directory $_: $!" for @mkdir;
    umask $umask;
    return;
}
sub _plate_file {
    defined $_[0]{path} ? $_[0]{path}.$_[1].$_[0]{suffix} : undef;
}
sub _cache_file {
    defined $_[0]{cache_path} ? $_[0]{cache_path}.$_[1].$_[0]{cache_suffix} : undef;
}
sub _load {
    my $plate = $_[0]->_plate_file($_[1]);
    my $cache = $_[0]->_cache_file($_[1]);
    my $_n;
    if (defined $cache) {
        if ($_[0]{static}) {
            return do $cache // croak $@ ? $@.'Plate compilation failed' : "Couldn't load $cache: $!" if -f $cache;
            $plate // croak "Plate template '$_[1]' does not exist";
        } else {
            $_n = $_[2] // (stat $plate)[9] // croak "Can't read $plate: $!";
            if (-f $cache and ($_[0]{mod}{$_[1]} // (stat _)[9]) >= $_n) {
                my $sub = do $cache // croak $@ ? $@.'Plate compilation failed' : "Couldn't load $cache: $!";
                $_[0]{mod}{$_[1]} //= $_n;
                return $sub;
            }
        }
        $_[0]->_make_cache_dir($_[1]);
    } elsif (defined $plate) {
        $_n = (stat $plate)[9] unless $_[0]{static} or exists $_[0]{mod}{$_[1]};
    } else {
        croak "Plate template '$_[1]' does not exist";
    }
    _compile $_[0]->_read($plate), $plate, $cache, $_[1], $_n;
}
sub _cached_sub {
    return $_[0]{mem}{$_[1]} //= $_[0]->_load($_[1]) if $_[0]{static} or not exists $_[0]{mod}{$_[1]};
    my $mod = (stat $_[0]->_plate_file($_[1]))[9]
        or croak "Plate template '$_[1]' does not exist";
    return $_[0]{mem}{$_[1]} //= $_[0]->_load($_[1], $mod) if $_[0]{mod}{$_[1]} == $mod;
    $_[0]{mem}{$_[1]} = $_[0]->_load($_[1], $mod);
}
sub _sub {
    $$Plate::_s{cache_code}
    ? $Plate::_s->_cached_sub($_[0])
    : $$Plate::_s{mem}{$_[0]} // $Plate::_s->_load($_[0]);
}

sub _empty {}
sub _r {
    my $tmpl = shift;
    if ($tmpl eq '_') {
        return undef unless @Plate::_c;
        if (defined(my $c = pop)) {
            local @Plate::_c = @Plate::_c;
            return &{splice @Plate::_c, -1, 1, $c};
        } else {
            $tmpl = pop @Plate::_c;
            local @Plate::_c = @Plate::_c;
            return &{$tmpl};
        }
    }
    if (@Plate::_c >= $$Plate::_s{max_call_depth}) {
        my($f, $l) = (caller 0)[1, 2];
        die "Call depth limit exceeded while calling \"$tmpl\" at $f line $l.\n";
    }
    local @Plate::_c = @Plate::_c;
    push @Plate::_c, pop // \&_empty;
    &{_sub $tmpl};
}
sub _f {
    goto &{$$Plate::_s{filters}{+shift}};
}

sub _path {
    my $path = $_[0];
    my $vol = WINDOWS ? $path =~ s'^[\\/]{2}(?=[^\\/])'' ? '//' : $path =~ s'^([a-zA-Z]:)'' ? ucfirst $1 : '' : '';
    length $path or return (length $vol or not $_[1]) ? $vol : './';
    my @dir = grep $_ ne '.', split WINDOWS ? qr'[\\/]+' : qr'/+', $path.'/', -1;
    $vol = './' if $_[1] and not length $vol and (length $dir[0] or @dir == 1);
    $vol.join('/', @dir);
}

{
    my %esc_html = ('"' => '&quot;', '&' => '&amp;', "'" => '&#39;', '<' => '&lt;', '>' => '&gt;');
    no warnings 'uninitialized';
    sub _basic_html_filter { $_[0] =~ s/(["&'<>])/$esc_html{$1}/egr }
}

=head1 SUBROUTINES/METHODS

=head2 new

    my $plate = Plate->new(%options);

Creates a new C<Plate> engine with the options provided.

Options (with their defaults) are:

=over

=item C<< auto_filter => 'html' >>

The name of the default filter to use for template variables when no filter is specified.
The built-in default filter is a very basic HTML filter.

To prevent the default filter being used for a single variable,
just set the filter to an empty string. Eg: C<< <% $unfiltered |%> >>

=item C<< cache_code => 1 >>

If set to a true value, the engine will cache compiled template code in memory.
This vastly improves performance at the expense of some memory.

=item C<< cache_path => undef >>

Set this to a directory to store compiled templates on the filesystem.
If the directory does not exist, it will attempt to create it using the C<umask> setting.

=item C<< cache_suffix => '.pl' >>

Compiled templates stored on the filesystem will have this suffix appended.

=item C<< chomp => 1 >>

If set to a true value, the final newline in every template will be removed.

=item C<< encoding => 'UTF-8' >>

Set this to the encoding of your template files.

=item C<< keep_undef => undef >>

If set to a false value (the default),
then variables and calls that return C<undef> are converted to an empty string.

=item C<< max_call_depth => 99 >>

This sets the maximum call depth to prevent infinite recursion.

=item C<< package => 'Plate::Template' >>

The package name that templates are compiled and run in.

=item C<< path => '' >>

The path to the templates on the filesystem.
If set to C<undef> then the filesystem will not be searched,
only cached templates will be served.

=item C<< static => undef >>

If set to a true value,
the engine will not reload the template when the file changes.

While this improves performance in production, it is not recommended in development.

=item C<< suffix => '.plate' >>

The suffix appended to template names when searching on the filesystem.

=item C<< umask => 077 >>

The C<umask> used when creating cache files and directories.

=back

=cut

sub new {
    my $class = shift;
    my $self = bless {
        auto_filter => 'html',
        cache_code => 1,
        cache_path => undef,
        cache_suffix => '.pl',
        chomp => 1,
        filters => {
            html => \&_basic_html_filter,
        },
        init => '',
        io_layers => ':encoding(UTF-8)',
        keep_undef => undef,
        max_call_depth => 99,
        mem => {},
        once => '',
        package => 'Plate::Template',
        path => '',
        static => undef,
        suffix => '.plate',
        umask => 077,
        vars => {},
    }, $class;
    $self->set(@_) if @_;
    $self;
}

=head2 serve

    my $output = $plate->serve($template_name, @arguments);

Renders a template.
The C<@arguments> will be passed to the template as C<@_>.

=head2 serve_with

    my $output = $plate->serve_with($content, $template_name, @arguments);

Renders a template with the provided content.

The content can be passed in one of three ways.
If C<$content> is a string then it is the name of a template to serve.
If C<$content> is a SCALAR ref then it is the contents of a template to be compiled and served.
C<$content> may also be a CODE ref which should return the content directly.

=cut

sub serve { shift->serve_with(undef, @_) }
sub serve_with {
    local $Plate::_s = shift;
    my($_c, $tmpl) = (shift // \&_empty, shift);
    _local_vars $$Plate::_s{package}, $$Plate::_s{vars};
    local @Plate::_c = ref $_c eq 'CODE' ? $_c : ref $_c eq 'SCALAR' ? _compile $$_c : _sub $_c;

    my $sub = ref $tmpl eq 'SCALAR'
    ? _compile $$tmpl
    : _sub $tmpl;
    &$sub;
}

=head2 content

Used from within a template to return the content for the template.

=cut

sub content {
    @Plate::_c ? do { local @Plate::_c = @Plate::_c; &{pop @Plate::_c} } : undef;
}

=head2 filter

    $plate->filter($filter_name => sub { ... });

Add a new filter for use in templates.
The subroutine will be given one argument (the content to filter) as a string,
and must return the filtered string.

=cut

sub filter {
    my($self, $name, $code) = @_;

    $name =~ /^\w+$/
        or croak "Invalid filter name '$name'";
    return delete $$self{filters}{$name} unless defined $code;
    ref $code eq 'CODE'
        or $code = ($code =~ /(.*)::(.*)/ ? $1->can($2) : do { my($i,$p) = 0; $i++ while __PACKAGE__ eq ($p = caller $i); $p->can($code) })
        or croak "Invalid subroutine '$_[2]' for filter '$name'";
    $$self{filters}{$name} = $code;
}

=head2 var

    $plate->var('$var' => \$var);
    $plate->var('%hash' => \%hash);
    $plate->var('@array' => \@array);
    $plate->var(func => \&func);
    $plate->var(CONST => 123);

Import a new local variable into the templating package for use by all templates.
All templates will have access to these variables even under C<use strict>.

To remove a var pass C<undef> as the value.

If the value is not a reference it will be a constant in the templating package.

=cut

my %sigil = (
    ARRAY => '@',
    CODE => '&',
    GLOB => '*',
    HASH => '%',
);
sub var {
    my($self, $name, $ref) = @_;

    defined $ref or return delete $$self{vars}{$name};

    my $sigil = $sigil{Scalar::Util::reftype $ref // 'CODE'} // '$';
    $name =~ s/^\Q$sigil\E?/$sigil ne '&' && $sigil/e;
    $$self{vars}{$name} = $ref;
}

=head2 define

    $plate->define($template_name => $content);

This will cache a template in memory.
The C<$content> is the contents of a template (as a string) to be compiled or a CODE ref.

=head2 undefine

    $plate->undefine;
    $plate->undefine($template_name);

This will delete a previously cached template,
or all templates if the name is C<undef>.

=cut

sub define {
    delete $_[0]{mod}{$_[1]} if $_[0]{mod};
    $_[0]{mem}{$_[1]} = ref $_[2] eq 'CODE' ? $_[2] : do {
        local($Plate::_s, @Plate::_c) = $_[0];
        _local_vars $$Plate::_s{package}, $$Plate::_s{vars};
        _compile $_[2], $_[1];
    };
}
sub undefine {
    if (defined $_[1]) {
        delete $_[0]{mod}{$_[1]};
        delete $_[0]{mem}{$_[1]};
    } else {
        delete $_[0]{mod};
        undef %{$_[0]{mem}};
    }
}

=head2 does_exist

    my $exists = $plate->does_exist($template_name);

Returns true if a template by that name is cached or exists on the filesystem.
No attempt will be made to compile the template.

=head2 can_serve

    my $ok = $plate->can_serve($template_name);

Returns true if a template by that name can be served,
otherwise it sets C<$@> to the reason for failure.

=cut

sub does_exist {
    $_[0]{cache_code} and not $_[0]{static} and exists $_[0]{mod}{$_[1]}
        and return -f $_[0]->_plate_file($_[1]);

    exists $_[0]{mem}{$_[1]} or -f($_[0]->_plate_file($_[1]) // $_[0]->_cache_file($_[1]));
}
sub can_serve {
    local $Plate::_s = $_[0];
    !!eval { _sub $_[1] };
}

=head2 set

    $plate->set(%options);

Set the options for this C<Plate> engine.
Options are the same as those for L</new>.

=cut

sub set {
    my($self, %opt) = @_;

    while (my($k, $v) = each %opt) {
        if ($k eq 'encoding') {
            $k = 'io_layers';
            $v = length $v ? $v eq 'utf8' ? ':utf8' : ":encoding($v)" : '';
        } elsif ($k eq 'path') {
            $v = _path $v if length $v;
        } elsif ($k eq 'cache_path') {
            # A relative cache_path must start with "./" to prevent searching @INC when sourcing the file
            $v = _path $v, 1 if defined $v;
        } elsif ($k =~ /^(?:(?:cache_)?suffix|init|io_layers|once)$/) {
            $v //= '';
        } elsif ($k eq 'filters' or $k eq 'vars') {
            my $method = substr $k, 0, -1;
            if (defined $v) {
                ref $v eq 'HASH' or croak "Invalid $k (not a hash reference)";
                $self->$method($_ => $$v{$_}) for keys %$v;
            } else {
                undef %{$$self{$k}};
            }
            next;
        } elsif ($k eq 'package') {
            defined $v and $v =~ /^[A-Z_a-z][0-9A-Z_a-z]*(?:::[0-9A-Z_a-z]+)*$/
                or croak "Invalid package name '".($v // '')."'";
        } elsif ($k !~ /^(?:auto_filter|cache_code|chomp|keep_undef|max_call_depth|static|umask)$/) {
            croak "Invalid setting '$k'";
        }
        $$self{$k} = $v;
    }

    if (defined $$self{path}) {
        undef $!;
        my $dir = length $$self{path} ? $$self{path} : '.';
        -d $dir and -r _ or croak "Can't set path to $dir: ".($! || 'Not accessable');
        undef $$self{static} if $$self{static} and $$self{static} eq 'auto';
    } else {
        $$self{static} ||= 'auto';
    }

    if (defined $$self{cache_path}) {
        my $dir = $$self{cache_path};
        if (-d $dir) {
            -w _ or croak "Cache directory $dir is not writeable";
        } else {
            my $umask = umask $$self{umask};
            (mkdir($dir), umask $umask)[0]
                or croak "Can't create cache directory $dir: $!";
        }
    } elsif (not $$self{cache_code}) {
        $$self{static} ||= 'auto';
    }
}

=head1 AUTHOR

Vernon Lyon C<< <vlyon@cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests on L<GitHub issues|https://github.com/vlyon/Plate/issues>.

=head1 SOURCE

The source code is hosted on L<GitHub|https://github.com/vlyon/Plate>.
Feel free to fork the repository and submit pull requests!

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Plate

You can also read the documentation online on L<metacpan|https://metacpan.org/pod/Plate>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2018, Vernon Lyon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
