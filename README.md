# NAME

DBIx::CLass::ValidationToo

# DESCRIPTION

Database validation plugin for DBIx::Class Result classess

# CONFIGURATION

Include this package as a component in your result class.
For each column definition needing validation, define a validation attribute.

    __PACKAGE__->load_components('ValidationToo');

    __PACKAGE__->add_column(
      column_name => {
        data_type => 'varchar',
        size => 100,
        validation => {
          is_required => 1,
          type => [qw(email unique)],
          validate_sub => sub {
            my ( $row, $value, $col ) = @_;
            return "John is not allowed" if $value =~ /john/i;
          }
        }
      }
    );

# VALIDATION

    $row = $schema->resultset('Thing')->create( \%thing );
    
    # Validate a single column against a given value
    $err_msg = $row->validate( email => 'happy@sad.net' );
    
    # Validate multiple columns against a href of values
    $err_href = $row->validate({
      foo => 'bar',
      bar => 'foo',
    });
    
    # Validate the values stored in all columns of the $row object
    $row->foo('bar');
    $row->bar('foo');
    $err_href = $row->validate;
    
    say "Column $_ - Error $err_href{$_}" for keys %$err_href;

# METHODS

## validate

Validates every column value currently stored in the $row object.
Returns a hashref of error messages keyed on column name.

    # Validate all data for all columns in object
    $err_href = $row->validate()
    
    # Validate a single column with a given value
    $err_msg = $row->validate('column' => $value);
    
    # Validate a hash of values
    $err_href = $row->validate(\%values);

## validate\_object

Validate all data for all columns in object

Upon validation error, returns a hashref of column error messages

Otherwise, returns undef

## validate\_href \\%columns

Given a hashref of column values, validate the hashref.  Data contained in
the validation hashref will not be stored onto the row object.

Upon validation error, returns a hashref of column error messages

Otherwise, returns undef

## validate\_column $column, \[$value\]

Validate a value for a column

If $value is not set, validates the value stored in the row object.  If $value
is set, $value will not be stored onto the row object.

Returns an error message string, or undef

Columns with no validation attribute hashes always pass validation.

Validation process:

- Check for is\_required
- Check each given validation type in the given order
- Run validation\_sub
- for varchar/char, check length <= size attribute

## get\_validation\_hash $column

Return the validation attribute hashref for $column

## test\_password\_strength $password \\%params

Check password strength with Data::Password

Since passwords should be stored hashed and salted, this is not used as
a standard validation type.  After including this component, you can
call the test\_password method on the row object.

Defaults for Data::Password can be overwritten with a parameter href.  The
default values are shown here:

Usage:

    my %params = (
      FOLLOWING  => 4, # forbid abcd, or 2345
      GROUPS     => 3, # forbid aaaa, or bbbb
      MINLEN     => 8,
      MAXLEN     => 64,
      DICTIONARY => 1, # enable dictionary checking
    )
    my $error_msg = $row->test_password( $password, \%params );

# VALIDATION TYPES

- int
- integer
- float
- money
- bool
- shortname

    For the URL identifier fields.  Allows
    \- numbers, letters, spaces, dashes, underscores

- email - Check E-Mail is valid
- percentage

    Check value is an int between 0-100

- template - Check Template fragment for errors
- text - Allow any text input
- time - SQL time column

    Value is in 24h time, with or without a seconds field.

    e.g: 12:45 or 19:05:00 or 12:3 or 11:30:25

- unique - value does not exist on any other record in the table.
- date - Check for validity of a date useing `DateTime::Format::DateParse`
- datetime - Column must contain a [DateTime](https://metacpan.org/pod/DateTime) object

    For use with [DBIx::Class::InflateColumn::DateTime](https://metacpan.org/pod/DBIx::Class::InflateColumn::DateTime)

- as\_phone

    Check string is a 10-digit number, after all non-numeric characters
    are discarded -- Assuming InflateColumn will be formatting the number
    as it's retreived, and strippping formatting as it's saved

# TODO

Create a way a column title string can be defined, and then used in error
messages.  "First Name is a required field" looks better than "first\_name is
a required field"

Make the size check for varchar/char columns optional

# AUTHOR

Mitch Jackson <mitch@mitchjacksontech.com>

# LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.
