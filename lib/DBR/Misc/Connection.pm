# the contents of this file are Copyright (c) 2009 Daniel Norman
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation.

package DBR::Misc::Connection;

use strict;
use base 'DBR::Common';

sub required_config_fields { [qw(database hostname user password)] };

sub new {
      my( $package ) = shift;

      my %params = @_;
      my $self = {
		  session  => $params{session},
		  dbh     => $params{dbh},
		 };

      bless( $self, $package );

      return $self->_error('session is required') unless $self->{session};
      return $self->_error('dbh is required')    unless $self->{dbh};
      $self->{lastping} = time; # assume the setup of the connection as being a good ping

      return $self;
}

sub dbh     { $_[0]->{dbh} }
sub do      { my $self = shift;  return $self->_wrap($self->{dbh}->do(@_))       }
sub prepare { my $self = shift;  return $self->_wrap($self->{dbh}->prepare(@_))  }
sub execute { my $self = shift;  return $self->_wrap($self->{dbh}->execute(@_))  }
sub selectrow_array { my $self = shift;  return $self->_wrap($self->{dbh}->selectrow_array(@_))  }
sub disconnect { my $self = shift; return $self->_wrap($self->{dbh}->disconnect(@_))  }
sub quote { shift->{dbh}->quote(@_)  }
sub quote_identifier { shift->{dbh}->quote_identifier(@_) }
sub can_lock { 1 }

sub table_ref {
    my ($self, $instance, $name) = @_;

    my $pname = $instance->prefix . $name;
    return $self->can('qualify_table') ? $self->qualify_table($instance, $pname) : $self->quote_identifier($pname);
}

# Default implementations of catalog query operators.
# Since every DBD seems to implement this a bit differently, feel free to override in subclasses!

# these four are meant to return something close to the DBI native format
sub table_info { my ($self, $inst) = @_; return $self->{_schema}{tbl}{$inst->database||''} ||= $self->_table_info($inst) }
sub primary_key_info { my ($self, $inst, $tbl) = @_; return $self->{_schema}{pk}{$inst->database||''}{$tbl} ||= $self->_primary_key_info($inst, $tbl) }
sub column_info { my ($self, $inst, $tbl) = @_; return $self->{_schema}{col}{$inst->database||''}{$tbl} ||= $self->_column_info($inst, $tbl) }
sub index_info { my ($self, $inst, $tbl) = @_; return $self->{_schema}{ix}{$inst->database||''}{$tbl} ||= $self->_index_info($inst, $tbl) }
sub fkey_info { my ($self, $inst, $tbl) = @_; return $self->{_schema}{fk}{$inst->database||''}{$tbl} ||= $self->_fkey_info($inst, $tbl) }

sub _table_info {
    my ($self, $db) = @_;
    local $self->{dbh}->{RaiseError} = 1;
    return [ grep { $_->{TABLE_TYPE} eq 'TABLE' } @{ $self->{dbh}->table_info('', $db->database)->fetchall_arrayref({}) } ];
}

sub _primary_key_info {
    my ($self, $db, $tbl) = @_;
    local $self->{dbh}->{RaiseError} = 1;
    return $self->{dbh}->primary_key_info(undef, $db->database, $tbl)->fetchall_arrayref({});
}

sub _column_info {
    my ($self, $db, $tbl) = @_;
    local $self->{dbh}->{RaiseError} = 1;
    return $self->{dbh}->column_info(undef, $db->database, $tbl, undef)->fetchall_arrayref({});
}

sub _index_info { [] } # not supported portably in DBI

sub _fkey_info { [] } # not supported portably in DBI

sub schema_info {
    my ($self, $inst) = @_;

    my %out;
    my $pfx = $inst->prefix;

    for my $tob (@{ $self->table_info($inst) }) {
        my $oname = $tob->{TABLE_NAME};
        my $name = $oname;
        $name =~ s/^\Q$pfx// or next;

        $out{$name} = $self->table_schema_info($inst, $oname);
    }

    return \%out;
}

sub flush_schema { delete $_[0]{_schema}; return $_[0] }

sub table_schema_info {
    my ($self, $inst, $oname) = @_;

    my $t = { columns => {}, indexes => {} };

    for my $c (@{ $self->column_info($inst, $oname) }) {
        $t->{columns}{$c->{COLUMN_NAME}} = {
            type => $c->{TYPE_NAME},
            max_value => $c->{COLUMN_SIZE},
            decimal_digits => $c->{DECIMAL_DIGITS},
            is_nullable => $c->{NULLABLE} ? 1 : 0,
            is_signed   => $c->{UNSIGNED} ? 0 : 1, # not DBI standard but set by a subclass
        };
    }

    for my $p (@{ $self->primary_key_info($inst, $oname) }) {
        my $c = $t->{columns}{$p->{COLUMN_NAME}} or next;
        $c->{is_pkey} = 1;
    }

    for my $i (@{ $self->index_info($inst, $oname) }) {
        my $io = $t->{indexes}{$i->{INDEX_NAME}} ||= { unique => $i->{NON_UNIQUE}?0:1, parts => [] };
        push @{$io->{parts}}, { column => $i->{COLUMN_NAME}, prefix_length => $i->{SUB_PART} };
    }

    for my $f (@{ $self->fkey_info($inst, $oname) }) {
        my $c = $t->{columns}{$f->{COLUMN_NAME}} or next;
        $c->{ref_dbname} = $f->{REFERENCED_TABLE_SCHEMA};
        $c->{ref_table} = $f->{REFERENCED_TABLE_NAME};
        $c->{ref_field} = $f->{REFERENCED_COLUMN_NAME};
    }

    return $t;
}

sub ping {
      my $self = shift;

      #$self->_logDebug3('PING'); # Logging is inefficient
      return 1 if $self->{lastping} + 2 > time; # only ping every 5 seconds

      #$self->_logDebug3('REAL PING'); # Logging is inefficient
      $self->{dbh}->ping or return undef;
      $self->{lastping} = time;
      return 1;
}

# if you throw an exception or call back into DBR (including to add hooks) from a rollback hook,
# DBR is not guaranteed to do anything remotely useful.
sub add_rollback_hook {
    my ($self, $hook) = @_;

    return unless $self->{_intran};
    push @{ $self->{_on_rollback} ||= [] }, $hook;
}

sub add_pre_commit_hook {
    my ($self, $hook) = @_;

    return $hook->() unless $self->{_intran};
    push @{ $self->{_pre_commit} ||= [] }, $hook;
}

sub add_post_commit_hook {
    my ($self, $hook) = @_;

    return $hook->() unless $self->{_intran};
    push @{ $self->{_post_commit} ||= [] }, $hook;
}

sub begin {
      my $self = shift;
      return $self->_error('Transaction is already open - cannot begin') if $self->{'_intran'};

      $self->_logDebug('BEGIN');
      $self->{dbh}->do('BEGIN') or return $self->_error('Failed to begin transaction');
      $self->{_intran} = 1;

      return 1;
}

sub commit{
      my $self = shift;
      return $self->_error('Transaction is not open - cannot commit') if !$self->{'_intran'};

      $self->_logDebug('COMMIT');

      my $precommit = $self->{_pre_commit};
      while ($precommit && @$precommit) {
          (shift @$precommit)->();
      }

      $self->{dbh}->do('COMMIT') or return $self->_error('Failed to commit transaction');

      $self->{_intran} = 0;

      my $postcommit = $self->{_post_commit};
      $self->{_on_rollback} = $self->{_pre_commit} = $self->{_post_commit} = undef;
      while ($postcommit && @$postcommit) {
          (shift @$postcommit)->();
      }

      return 1;
}

sub rollback{
      my $self = shift;
      return $self->_error('Transaction is not open - cannot rollback') if !$self->{'_intran'};

      $self->_logDebug('ROLLBACK');
      $self->{dbh}->do('ROLLBACK') or return $self->_error('Failed to rollback transaction');

      $self->{_intran} = 0;

      my $hooks = $self->{_on_rollback};
      $self->{_on_rollback} = $self->{_pre_commit} = $self->{_post_commit} = undef;
      while ($hooks && @$hooks) {
          (pop @$hooks)->();
      }

      return 1;
}

######### ability check stubs #########

sub can_trust_execute_rowcount{ 0 }

############ sequence stubs ###########
sub prepSequence{
      return 1;
}
sub getSequenceValue{
      return -1;
}
#######################################

sub b_intrans{ $_[0]->{_intran} ? 1:0 }
sub b_nestedTrans{ 0 }

sub quiet_next_error{
      my $self = shift;

      $self->{dbh}->{PrintError} = 0;

      return 1;
}

sub _wrap{
      my $self = shift;

      #reset any variables now
      $self->{dbh}->{PrintError} = 1;

      return wantarray?@_:$_[0];
}
1;
