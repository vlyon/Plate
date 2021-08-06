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

# DESCRIPTION

Plate is a very fast, efficient and full-featured templating engine.

Inspired by [HTML::Mason](https://metacpan.org/pod/HTML::Mason) and [Tenjin](https://metacpan.org/pod/Tenjin), the goal of this templating engine is speed and functionality.
It has no non-core dependencies, is a compact size and supports embedded Perl.

Features include preprocessing templates,
caching compiled templates,
variable escaping/filtering,
localised global variables.
Templates can also include other templates, with optional content
and even define or override templates locally.

All templates have strict, warnings, utf8 and Perl 5.20 features enabled.

## Example

Here is an example template for a letter stored in the file: `letter.plate`

```perl
% my($title, $surname) = @_;
Dear <% $title %> <% $surname %>,

<& _ &>

    Kind Regards,

    E. X. Ample
```

Another template could _include_ this template, Eg: `job.plate`

```perl
<&| letter, 'Dr.', 'No' &>\
In response to the recently advertised position, please
consider my résumé in your search for a professional sidekick.
</&>
```

Serving the `job.plate` template will result in the following output:

```perl
Dear Dr. No,

In response to the recent advertised position, please
consider my résumé in your search for a professional sidekick.

        Kind Regards,

        E. X. Ample
```

Here is the code to render this output:

```perl
use Plate;

my $plate = new Plate;
my $output = $plate->serve('job');
```

## Markup

### Variables

```
<% $var %>
<% $unescaped |%>
<% $filtered |trim |html %>
```

Variables are interpolated into the output and optionally filtered (escaped).
Filters are listed in the order to be applied preceded by a `|` character.
If no filter is given as in the first example, then the default filter is applied.
To explicitly avoid the default filter use the empty string as a filter.

### Statements

```perl
% my $user = db_lookup(user => 'bob');
% for my $var (@list) {
```

Lines that start with a `%` character are treated as Perl statements.

### Comments

```
%# Comment line
<% # inline comment %>
<%#
    Multi-line
    comment
%>
```

### Perl blocks

```
<%perl>
...
</%perl>
```

Perl code can also be wrapped in a perl block.

### Newlines

Newline characters can be escaped with a backslash, Eg:

```perl
% for my $var ('a' .. 'c') {
<% $var %>\
% }
```

This will result in the output `abc`, all on one line.

### Content

```
<& _ &>
```

A template can be served with content. This markup will insert the content provided, if any.

### Include other templates

```
<& header, 'My Title' &>
...
<& footer &>
```

A template can include other templates with optional arguments.

### Include other templates with provided content

```
<&| paragraph &>
This content is passed to the "paragraph" template.
</&>

Plain text, <&| bold &>bold text</&>, plain text.
```

An included template can have its own content passed in.

### Def blocks

```perl
<%def copyright>
Copyright © <% $_[0] %>
</%def>

<& copyright, 2018 &>
```

Local templates can be defined in a template.
They can even override existing templates.

# SUBROUTINES/METHODS

## new

```perl
my $plate = Plate->new(%options);
```

Creates a new `Plate` engine with the options provided.

Options (with their defaults) are:

- `auto_filter => 'html'`

    The name of the default filter to use for template variables when no filter is specified, `<% ... %>`.
    The built-in default filter is a very basic HTML filter.
    Set this to `undef` to disable the default filter.

    To prevent the default filter being used for just a single variable,
    just set the filter to an empty string. Eg: `<% $unfiltered |%>`

- `cache_code => 1`

    If set to a true value, the engine will cache compiled template code in memory.
    This vastly improves performance at the expense of some memory.

- `cache_path => undef`

    Set this to a directory to store compiled templates on the filesystem.
    If the directory does not exist, it will attempt to create it using the `umask` setting.

- `cache_suffix => '.pl'`

    Compiled templates stored on the filesystem will have this suffix appended.

- `chomp => 1`

    If set to a true value (the default),
    the final newline in every template will be removed.

- `encoding => 'UTF-8'`

    Set this to the encoding of your template files.

- `filters => { html => \&_basic_html_filter }`

    A hash of filters to set for use in templates.
    The key is the name of the filter, and the value is the CODE ref, subroutine name or `undef`.
    The subroutine will be given one argument (the content to filter) as a string,
    and must return the filtered string.
    To remove a filter pass `undef` as it's value.

    To remove all filters pass `undef` instead of a HASH ref.

- `keep_undef => undef`

    If set to a false value (the default),
    then variables and calls that return `undef` are converted to an empty string.

- `max_call_depth => 99`

    This sets the maximum call depth to prevent infinite recursion.

- `package => 'Plate::Template'`

    The package name that templates are compiled and run in.

- `path => ''`

    The path to the templates on the filesystem.
    An empty string (the default) refers to the current directory.
    If set to `undef` then the filesystem will not be searched,
    only cached templates will be served.

- `static => undef`

    If set to a false value (the default),
    the engine will reload and recompile templates whenever files are modified.

    If set to a true value,
    file modification will not be checked nor will templates be reloaded.
    While this improves performance in production, it is not recommended in development.

- `suffix => '.plate'`

    The suffix appended to template names when searching on the filesystem.

- `umask => 077`

    The `umask` used when creating cache files and directories.

- `vars => {}`

    A hash of vars to set for use in templates.
    This will define new local variables to be imported into the templating package when compiling and running templates.
    If the value is not a reference it will be a constant in the templating package.
    To remove a var pass `undef` as it's value.

    To remove all vars pass `undef` instead of a HASH ref.

    All templates will have access to these variables, subroutines and constants even under `use strict`.

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

```perl
% my $content = &Plate::content;
```

Used from within a template to return the content passed to that template.

## has\_content

```
% if (Plate::has_content) { ...
```

Used from within a template to determine if that template was called with content.

## define

```perl
$plate->define($template_name => $content);
```

This will cache a template in memory.
The `$content` is the contents of a template (as a string) to be compiled or a CODE ref.

This is useful if you need to use templates that are not stored on the file system,
for example from a database or a custom subroutine.

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

Please report any bugs or feature requests on [GitHub issues](https://github.com/vlyon/Plate/issues).

# SOURCE

The source code is hosted on [GitHub](https://github.com/vlyon/Plate).
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
