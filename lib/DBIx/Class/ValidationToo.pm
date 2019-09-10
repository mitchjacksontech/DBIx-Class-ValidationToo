package DBIx::Class::ValidationToo;
use base 'DBIx::Class';
use Modern::Perl;

our $VERSION = 0.2;

# Many validation methods may use undef in a regex
no warnings 'uninitialized';

use Carp qw( carp );
use Data::Password qw( :all $DICTIONARY );
use DateTime::Format::DateParse;

=head1 NAME

DBIx::CLass::ValidationToo

=head1 DESCRIPTION

Database validation plugin for DBIx::Class Result classess

=head1 CONFIGURATION

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

=head1 VALIDATION

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

=head1 METHODS

=head2 validate

Validates every column value currently stored in the $row object.
Returns a hashref of error messages keyed on column name.

  # Validate all data for all columns in object
  $err_href = $row->validate()
  
  # Validate a single column with a given value
  $err_msg = $row->validate('column' => $value);
  
  # Validate a hash of values
  $err_href = $row->validate(\%values);

=cut

sub validate {
    my $self = shift;

    return $self->validate_object unless @_;
    return $self->validate_href if ref $_[0];
    return $self->validate_column(@_);
}

=head2 validate_object

Validate all data for all columns in object

Upon validation error, returns a hashref of column error messages

Otherwise, returns undef

=cut

sub validate_object {
    my $self = shift;
    my %error;

    for my $col ( $self->columns ) {
        if ( my $error = $self->validate_column( $col, $self->$col ) ) {
            $error{$col} = $error;
        }
    }

    %error ? \%error : undef;
}

=head2 validate_href \%columns

Given a hashref of column values, validate the hashref.  Data contained in
the validation hashref will not be stored onto the row object.

Upon validation error, returns a hashref of column error messages

Otherwise, returns undef

=cut

sub validate_href {
    my ($self, $validate) = @_;
    my %error;

    for my $col ( keys %{$validate} ) {
        if ( $self->can($col) ) {
            if ( my $error = $self->validate_column( $col, $self->$col )) {
                $error{$col} = $error;
            }
        } else {
            $error{$col} = "Invalid column name";
        }
    }

    %error ? \%error : undef;
}

=head2 validate_column $column, [$value]

Validate a value for a column

If $value is not set, validates the value stored in the row object.  If $value
is set, $value will not be stored onto the row object.

Returns an error message string, or undef

Columns with no validation attribute hashes always pass validation.

Validation process:

=over 4

=item Check for is_required

=item Check each given validation type in the given order

=item Run validation_sub

=item for varchar/char, check length <= size attribute

=back

=cut

sub validate_column {
    my ($self, $col, $val) = @_;
    my $v = $self->get_validation_hash($col) || return;

    return "Field is required"
        if $v->{is_required}
        && ( !defined $val || $val eq '' );

    return undef unless defined $val;

    if ( $v->{type} ) {
        for my $type ( ref $v->{type} ? @{$v->{type}} : $v->{type} ) {
            my $vmethod = "as_$type";
            carp "Unknown validation type ($type)" unless $self->can($vmethod);
            if( my $error_msg = $self->$vmethod( $val, $col ) ) {
                return $error_msg;
            }
        }
    }

    if ( ref $v->{validate_sub} ) {
        if ( my $error_msg = $v->{validate_sub}->( $self, $val, $col )) {
            return $error_msg;
        }
    }

    my $ci = $self->column_info($col);
    return "Can not exceed $ci->{size} characters"
        if ( $ci->{data_type} eq 'varchar' || $ci->{data_type} eq 'char' )
        && $ci->{size} < length( $val );

    undef;
}

=head2 get_validation_hash $column

Return the validation attribute hashref for $column

=cut

sub get_validation_hash {
    my ($self, $col) = @_;
    my $ci = $self->column_info($col) || carp "bad column name: $col";
    return ref $ci->{validation} ? $ci->{validation} : undef;
}

=head2 test_password_strength $password \%params

Check password strength with Data::Password

Since passwords should be stored hashed and salted, this is not used as
a standard validation type.  After including this component, you can
call the test_password method on the row object.

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

=cut

sub test_password_strength {
    my ($self, $value, $param) = @_;
    my %param = ref $param ? %{$param} : ();

    $Data::Password::FOLLOWING = $param{FOLLOWING} || 8;
    $Data::Password::GROUPS    = $param{GROUPS}    || 3;
    $Data::Password::MINLEN    = $param{MINLEN}    || 8;
    $Data::Password::MAXLEN    = $param{MAXLEN}    || 64;
    $DICTIONARY = undef unless $param{DICTIONARY};

    IsBadPassword( $value );
}

=head1 VALIDATION TYPES

=over 4

=item int

=cut

sub as_int { $_[1] =~ /\D/ ? "Not a valid number" : undef; }

=item integer

=cut

sub as_integer { as_int($_[1]) }

=item float

=cut

sub as_float { $_[1] =~ /^\d+\.\d+$/ ? undef : "Not a valid number"; };

=item money

=cut

sub as_money { $_[1] =~ /\d+(?:\.\d{2})?$/ ? undef : "Not a valid dollar amount"; };

=item bool

=cut

sub as_bool { ($_[1] == 0 || $_[1] == 1) ? undef : "Not a valid boolean"; };

=item shortname

For the URL identifier fields.  Allows
- numbers, letters, spaces, dashes, underscores

=cut

sub as_shortname {
    my ($self, $value, $col) = @_;
    $value =~ /^[\d\w\-\_]+$/
        ? undef
        : "Only letters, numbers, (-) and (_) are allowed";
}

=item email - Check E-Mail is valid

=cut

sub as_email {
    my ($self, $value, $col) = @_;
    Email::Valid->address( $value ) ? undef : 'Invalid E-Mail address';
}

=item percentage

Check value is an int between 0-100

=cut

sub as_percentage {
    my ( $self, $value, $col ) = @_;
    ( $value =~ /^\d+/ && $value >= 0 && $value <= 100 )
    ? undef
    : "Requires a whole number between 0-100";
}

=item template - Check Template fragment for errors

=cut

sub as_template {
    my ( $self, $value, $col ) = @_;
    my $tt = Template->new({ EVAL_PERL => 0 });
    $tt->process( \$value ) ? undef : $tt->error->as_string;
}

=item text - Allow any text input

=cut

sub as_text {
    undef;
}

=item time - SQL time column

Value is in 24h time, with or without a seconds field.

e.g: 12:45 or 19:05:00 or 12:3 or 11:30:25

=cut

sub as_time {
    my ( $self, $value, $col) = @_;
    $value =~ /^\d\d?\:\d\d?(?:\:\d\d?)?$/
    ? undef
    : "Invalid 24h time format: $value"
}

=item unique - value does not exist on any other record in the table.

=cut

sub as_unique {
    my ($self, $value, $col) = @_;
    my $rs =  $self->result_source->resultset->search({ $col => $value });

    if ( $self->in_storage ) {
        for my $pk ( $self->primary_columns ) {
            $rs = $rs->search({ $pk => {'!=' => $self->$pk} });
        }
    }

    $rs->count ? "$value is already in use" : undef;
}

=item date - Check for validity of a date useing C<DateTime::Format::DateParse>

=cut

sub as_date {
    my ($self, $value, $col) = @_;
    my $dt;
    eval{ $dt = DateTime::Format::DateParse->parse_datetime( $value ) };
    $dt ? undef : "Invalid date format";
}

=item datetime - Column must contain a L<DateTime> object

For use with L<DBIx::Class::InflateColumn::DateTime>

=cut

sub as_datetime {
    my ($self, $value, $col) = @_;
    return
        if $value
        && ref $value
        && $value->isa('DateTime');
    'Invalid date/time format';
}

=item as_phone

Check string is a 10-digit number, after all non-numeric characters
are discarded -- Assuming InflateColumn will be formatting the number
as it's retreived, and strippping formatting as it's saved

=cut

sub as_phone {
    # Assuming phone columns will be inflat
    my ($self, $value, $col) = @_;
    $value =~ s/\D//g;
    $value =~ /^\d{10}$/ ? undef : 'A 10-digit phone number is required';
}

=back

=head1 TODO

Create a way a column title string can be defined, and then used in error
messages.  "First Name is a required field" looks better than "first_name is
a required field"

Make the size check for varchar/char columns optional

=head1 AUTHOR

Mitch Jackson <mitch@mitchjacksontech.com>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;