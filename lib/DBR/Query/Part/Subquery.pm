# the contents of this file are Copyright (c) 2009 Daniel Norman
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation.

###########################################
package DBR::Query::Part::Subquery;
use strict;
use base 'DBR::Query::Part';

sub new{
      my( $package ) = shift;
      my ($field,$query) = @_;

      return $package->_error('field must be a Field object') unless ref($field) =~ /^DBR::Config::Field/; # Could be ::Anon
      return $package->_error('value must be a Value object') unless ref($query) eq 'DBR::Query';

      my $self = [ $field, $query ];

      bless( $self, $package );
      return $self;
}

sub type { return 'SUBQUERY' };
sub field   { return $_[0]->[0] }
sub query { return $_[0]->[1] }
sub sql   { return $_[0]->field->sql . ' IN (' . $_[0]->query->sql . ')'}

sub _validate_self{ 1 }

1;

###########################################


1;