# NAME

Plate - Fast templating engine with support for embedded Perl

# SYNOPSIS

```perl
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
```

# SUBROUTINES/METHODS

## new

```perl
my $plate = Plate->new(%options);
```

Creates a new `Plate` engine with the options provided.

Options (with their defaults) are:

- `auto_filter => 'html'`

    The name of the default filter to use for template variables when no filter is specified.
    The built-in default filter is a very basic HTML filter.

    To prevent the default filter being used for a single variable,
    just set the filter to an empty string. Eg: `<% $unfiltered |%>`

- `cache_code => undef`

    If set to a true value, the engine will cache compiled templates in memory.

- `cache_path => undef`

    Set this to a directory to store compiled templates on the filesystem.
    If the directory does not exist, it will attempt to create it using the `umask` setting.

- `cache_suffix => '.pl'`

    Compiled templates stored on the filesystem will have this suffix appended.

- `encoding => 'UTF-8'`

    Set this to the encoding of your template files.

- `keep_undef => undef`

    If set to a false value (the default),
    then variables and calls that return `undef` are converted to an empty string.

- `max_call_depth => 99`

    This sets the maximum call depth to prevent infinite recursion.

- `path => ''`

    The path to the templates on the filesystem.
    If set to `undef` then the filesystem will not be searched,
    only cached templates will be served.

- `static => undef`

    If set to a true value,
    the engine will not reload the template when the file changes.

    While this improves performance in production, it is not recommended in development.

- `suffix => '.plate'`

    The suffix appended to template names when searching on the filesystem.

- `umask => 077`

    The `umask` used when creating cache files and directories.

## serve

```perl
my $output = $plate->serve($template_name, @arguments);
```

Renders a template.
The `@arguments` will be passed to the template as `@_`.

## serve\_with

```perl
my $output = $plate->serve_with($content, $template_name, @arguments);
```

Renders a template with the provided content.

The content can be passed in one of three ways.
If `$content` is a string then it is the name of a template to serve.
If `$content` is a SCALAR ref then it is the contents of a template to be compiled and served.
`$content` may also be a CODE ref which should return the content directly.

## content

Used from within a template to return the content for the template.

## filter

```perl
$plate->filter($filter_name => sub { ... });
```

Add a new filter for use in templates.
The subroutine will be given one argument (the content to filter) as a string,
and must return the filtered string.

## global

```perl
$plate->global(var => $var);
$plate->global(hash => \%hash);
$plate->global(array => \%array);
$plate->global(func => \&func);
```

Import a new variable into the `Plate::Template` package for use by all templates.
All templates will have access to these variables even under `use strict`.

To remove a global pass `undef` as the value.

Globals must have unique names.
You can't have different reference types with the same name like `$var` and `@var`.
When adding a global variable, if one by the same name already exists, it will be replaced.

## define

```perl
$plate->define($template_name => $content);
```

This will cache a template in memory.
The `$content` is the contents of a template (as a string) to be compiled or a CODE ref.

## undefine

```
$plate->undefine;
$plate->undefine($template_name);
```

This will delete a previously cached template,
or all templates if the name is `undef`.

## does\_exist

```perl
my $exists = $plate->does_exist($template_name);
```

Returns true if a template by that name is cached or exists on the filesystem.
No attempt will be made to compile the template.

## can\_serve

```perl
my $ok = $plate->can_serve($template_name);
```

Returns true if a template by that name can be served,
otherwise it sets `$@` to the reason for failure.

## set

```
$plate->set(%options);
```

Set the options for this `Plate` engine.
Options are the same as those for ["new"](#new).

# AUTHOR

Vernon Lyon `<vlyon@cpan.org>`

# BUGS

Please report any bugs or feature requests on [GitHub issues](https://github.com/vlyon/plate/issues).

# SOURCE

The source code is hosted on [GitHub](https://github.com/vlyon/plate).
Feel free to fork the repository and submit pull requests!

# SUPPORT

You can find documentation for this module with the perldoc command.

```
perldoc Plate
```

You can also read the documentation online on [metacpan](https://metacpan.org/pod/Plate).

# COPYRIGHT AND LICENSE

Copyright (C) 2018, Vernon Lyon.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
