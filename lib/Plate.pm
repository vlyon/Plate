use 5.020;
use warnings;
package Plate 0.1;

use Alias ();
use Carp 'croak';
use File::Spec;

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
    ^<%%def\h+([\w/\.-]+)>(?:\n|\z)|
    ^%%\h*(\N*?)\h*(?:\n|\z)|
    <%%\h*(.+?)\h*(?:\|\h*(|\w+(?:\h*\|\h*\w+)*)\h*)?%%>|
    <&&(\|)?\h*(.+?)\h*(?:\|\h*(|\w+(?:\h*\|\h*\w+)*)\h*)?&&>|
    </(%%def)>(?:\n|\z)|
    </(&&)>|\z
)'mosx;
my $re_run = qr'(.*?)(?:
    ^<%def\h+([\w/\.-]+)>(?:\n|\z)|
    ^%\h*(\N*?)\h*(?:\n|\z)|
    <%\h*(.+?)\h*(?:\|\h*(|\w+(?:\h*\|\h*\w+)*)\h*)?%>|
    <&(\|)?\h*(.+?)\h*(?:\|\h*(|\w+(?:\h*\|\h*\w+)*)\h*)?&>|
    </(%def)>(?:\n|\z)|
    </(&)>|\z
)'mosx;

sub _parse_text {
    my $text = $_[0];
    $_[2] = $text =~ s/\\\n//g if $_[1] == $re_run;
    $text =~ s/(\\|')/\\$1/g;
    length $text ? "'$text'" : ();
}
sub _parse_cmnt {
    $_[0] =~ /^#(?:\s*line\s+(\d+)\s*(?:\s("?)([^"]+)\g2)?\s*|.*)$/
    ? defined $1
        ? "\n#line $1".(defined $3 && " $3")
        : ''
    : $_[0];
}
sub _parse_call {
    'Plate::_r('.($_[0] =~ /^([\w\/\.-]+)\s*(?:,\s*(.*))?$/ ? length $2 ? "'$1',($2)" : "'$1'" : $_[0]).',';
}
sub _parse_defn {
    $_[0] =~ /\W/ ? "'".($_[0] =~ s/(\\|')/\\$1/gr)."'" : $_[0];
}
sub _parse_fltr {
    my $expr = "do{$_[0]}";
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
sub _pre_line { '"\\\\\n%#line ".__LINE__."\n"' }
sub _parse {
    my @expr;
    my $stmt;
    while ($_[0] =~ /$_[1]/g) {

        if (length $1) {
            push @expr, _parse_text $1, $_[1], my $add_lines;
            (@expr ? $expr[-1] : defined $stmt ? $stmt : ($expr[0] = "''")) .= "\n" x $add_lines if $add_lines;
        }

        if (defined $2) {
            # <%def ...>
            if (defined $stmt) {
                if (@expr) {
                    unshift @expr, _pre_line if $_[1] == $re_pre;
                    $stmt .= '$Plate::_b.='.join('.', splice @expr).';';
                }
            } else {
                $stmt = 'local$Plate::_b='.(@expr ? join('.', splice @expr) : "''").';';
            }
            local $_[3] = ($_[1] == $re_pre && '%').'%def';
            $stmt .= 'local$$Plate::_s{mem}{'._parse_defn(my $def = $2)."}=\n".&_parse.';';

        } elsif (defined $3) {
            # % ...
            if (defined $stmt) {
                if (@expr) {
                    unshift @expr, _pre_line if $_[1] == $re_pre;
                    $stmt .= '$Plate::_b.='.join('.', splice @expr).';';
                }
            } else {
                $stmt = 'local$Plate::_b='.(@expr ? join('.', splice @expr) : "''").';';
            }
            $stmt .= _parse_cmnt $3;
            $stmt .= "\n";

        } elsif (defined $4) {
            # <% ... %>
            push @expr, _parse_fltr $4, $5 // $$Plate::_s{auto_filter};

        } elsif (defined $7) {
            # <& ... &> or <&| ... &>
            if ($7 eq '_') {
                push @expr, _parse_fltr '&Plate::content', $8;
            } else {
                if (defined $stmt) {
                    unshift @expr, _pre_line if $_[1] == $re_pre and @expr;
                    $stmt .= '$Plate::_b.=';
                } else {
                    $stmt = 'local$Plate::_b=';
                }
                local $_[3] = ($_[1] == $re_pre && '&').'&' if defined $6;
                $stmt .= join('.', splice(@expr), _parse_fltr _parse_call($7).(defined $6 ? &_parse : 'undef').')', $8)
                .';pop@Plate::_c;';
            }

        } else {
            # </%def> or </&> or \z
            my $tag = $9 // $10 // '';
            if ($tag ne $_[3]) {
                my $line = 1 + join('', $stmt // '', @expr) =~ y/\n//;
                $line = "at $_[2] line $line.\nPlate ".($_[1] == $re_pre && 'pre').'compilation failed';
                croak $tag
                ? "Closing </$tag> tag without opening <$tag...> tag $line"
                : "Opening <$_[3]...> tag without closing </$_[3]> tag $line";
            }

            my $pl = (not $_[3] and $$Plate::_s{alias_args}) ? 'Alias::attr(shift);' : '';
            if (defined $stmt) {
                unshift @expr, _pre_line if $_[1] == $re_pre and @expr;
                $pl .= $stmt.join('.', '$Plate::_b', @expr);
            } else {
                $pl .= @expr ? join('.', @expr) : "''";
            }
            $pl .= "\n" if defined $9;
            return "sub{$pl}";
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
    open my $fh, '>:utf8', $_[0]
        or croak "Can't write $_[0]: $!";
    print $fh $_[1];
    umask $umask;
}
sub _eval {
    package # Dont index on PAUSE
        Plate::Template;
    eval $_[0];
}
sub _compile {
    my($file, $line) = length $_[1] ? ($_[1], "#line 1 $_[1]\n") : ('-', '');
    my $pl = _eval $line._parse($_[0], $re_pre, $file, '')
        or croak $@.'Plate precompilation failed';
    $pl = eval { $pl->() }
        or croak $@.'Plate precompilation failed';
    $pl = _parse $pl, $re_run, $file, '';
    $line .= "no strict 'vars';" if $$Plate::_s{alias_args};
    _write $_[2], "use 5.020;use warnings;use utf8;\n".$line.$pl if length $_[2];
    _eval $line.$pl
        or croak $@.'Plate compilation failed';
}
sub _make_cache_dir {
    my($dir, @mkdir) = $_[1];
    unshift @mkdir, $_[0]{cache_path}.$dir until $dir !~ s|/[^/]*$|| or -d $_[0]{cache_path}.$dir;
    mkdir $_, $_[0]{umask} or croak "Can't create cache directory $_: $!" for @mkdir;
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
    if ($cache) {
        if (-f $cache and ($_[0]{static} or ($_[0]{mod}{$_[1]} // (stat _)[9]) >= ($_[0]{mod}{$_[1]} = $_[2] // (stat $plate)[9]))) {
            return do { package # Dont index on PAUSE
                Plate::Template;
                do $cache;
            } // croak $@ ? $@.'Plate compilation failed' : "Couldn't load $cache: $!";
        }
        $plate // croak "Plate template '$_[1]' does not exist";
        $_[0]->_make_cache_dir($_[1]);
    } elsif (defined $plate) {
        $_[0]{mod}{$_[1]} //= (stat $plate)[9] unless $_[0]{static};
    } else {
        croak "Plate template '$_[1]' does not exist";
    }
    _compile $_[0]->_read($plate), $plate, $cache;
}
sub _cached_sub {
    return $_[0]{mem}{$_[1]} //= $_[0]->_load($_[1]) if $_[0]{static} or not exists $_[0]{mod}{$_[1]};
    my $mod = (stat $_[0]->_plate_file($_[1]))[9] // croak "Plate template '$_[1]' does not exist";
    return $_[0]{mem}{$_[1]} if $_[0]{mod}{$_[1]} == $mod;
    $_[0]{mem}{$_[1]} = $_[0]->_load($_[1], $mod);
}
sub _sub {
    $$Plate::_s{cache_code}
    ? $Plate::_s->_cached_sub($_[0])
    : ($$Plate::_s{mem}{$_[0]} // $Plate::_s->_load($_[0]));
}

sub _empty {}
sub _r {
    my $tmpl = shift;
    push @Plate::_c, pop // \&_empty;
    if (@Plate::_c > $$Plate::_s{max_call_depth}) {
        my($f, $l) = (caller 0)[1, 2];
        die "Call depth limit exceeded while calling \"$tmpl\" at $f line $l.\n";
    }
    goto(_sub $tmpl);
}
sub _f {
    goto &{$$Plate::_s{filters}{+shift}};
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

=item C<< cache_code => undef >>

If set to a true value, the engine will cache compiled templates in memory.

=item C<< cache_path => undef >>

Set this to a directory to store compiled templates on the filesystem.
If the directory does not exist, it will attempt to create it using the C<umask> setting.

=item C<< cache_suffix => '.pl' >>

Compiled templates stored on the filesystem will have this suffix appended.

=item C<< encoding => 'UTF-8' >>

Set this to the encoding of your template files.

=item C<< keep_undef => undef >>

If set to a false value (the default),
then variables and calls that return C<undef> are converted to an empty string.

=item C<< max_call_depth => 99 >>

This sets the maximum call depth to prevent infinite recursion.

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
        alias_args => undef,
        auto_filter => 'html',
        cache_code => undef,
        cache_path => undef,
        cache_suffix => '.pl',
        filters => {
            html => \&_basic_html_filter,
        },
        globals => {
            content => \&content,
        },
        keep_undef => undef,
        io_layers => ':encoding(UTF-8)',
        max_call_depth => 99,
        mem => {},
        path => '',
        static => undef,
        suffix => '.plate',
        umask => 077,
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
    local($Alias::AttrPrefix, $Plate::_s, @Plate::_c) = ('Plate::Template::', shift, shift // \&_empty);
    Alias::attr $$Plate::_s{globals};
    $Plate::_c[0] = ref $Plate::_c[0] eq 'SCALAR' ? _compile ${$Plate::_c[0]} : _sub $Plate::_c[0] if ref $Plate::_c[0] ne 'CODE';
    my $tmpl = shift;

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
    ref $code eq 'CODE'
        or $code = ($code =~ /(.*)::(.*)/ ? $1->can($2) : do { my($i,$p) = 0; $i++ while __PACKAGE__ eq ($p = caller $i); $p->can($code) })
        or croak "Invalid subroutine '$_[2]' for filter '$name'";
    $$self{filters}{$name} = $code;
}

=head2 global

    $plate->global(var => $var);
    $plate->global(hash => \%hash);
    $plate->global(array => \%array);
    $plate->global(func => \&func);

Import a new variable into the C<Plate::Template> package for use by all templates.
All templates will have access to these variables even under C<use strict>.

To remove a global pass C<undef> as the value.

Globals must have unique names.
You can't have different reference types with the same name like C<$var> and C<@var>.
When adding a global variable, if one by the same name already exists, it will be replaced.

=cut

sub global {
    my($self, $name, $ref) = @_;

    defined $ref ? $$self{globals}{$name} = $ref : delete $$self{globals}{$name};
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
    $_[0]{mem}{$_[1]} = ref $_[2] eq 'CODE' ? $_[2] : do {
        local($Alias::AttrPrefix, $Plate::_s, @Plate::_c) = ('Plate::Template::', $_[0]);
        Alias::attr $$Plate::_s{globals};
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
            $v = substr File::Spec->catfile($v, 'x'), 0, -1 if length $v;
        } elsif ($k eq 'cache_path') {
            if (defined $v) {
                $v = '.' unless length $v;
                $v = File::Spec->catfile($v, 'x');
                # A relative cache_path must start with "./" to prevent searching @INC when sourcing the file
                $v = File::Spec->catfile('.', $v) unless File::Spec->file_name_is_absolute($v);
                $v = substr $v, 0, -1;
            }
        } elsif ($k =~ /^(?:(?:cache_)?suffix|io_layers)$/) {
            $v //= '';
        } elsif ($k eq 'filters' or $k eq 'globals') {
            $v //= {};
            ref $v eq 'HASH' or croak "Invalid $k (not a hash reference)";
            my $method = substr $k, 0, 6;
            $self->$method($_ => $$v{$_}) for keys %$v;
            next;
        } elsif ($k !~ /^(?:alias_args|auto_filter|cache_code|keep_undef|max_call_depth|static|umask)$/) {
            croak "Invalid setting '$k'";
        }
        $$self{$k} = $v;
    }

    if (defined $$self{path}) {
        my $dir = length $$self{path} ? $$self{path} : '.';
        -d $dir and -r _ or croak "Can't set path to $dir: ".($! // 'Not accessable');
        undef $$self{static} if $$self{static} and $$self{static} eq 'auto';
    } else {
        $$self{static} ||= 'auto';
    }

    if (defined $$self{cache_path}) {
        my $dir = $$self{cache_path};
        if (-d $dir) {
            -w _ or croak "Cache directory $dir is not writeable";
        } else {
            mkdir $dir, $$self{umask} or croak "Can't create cache directory $dir: $!";
        }
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
