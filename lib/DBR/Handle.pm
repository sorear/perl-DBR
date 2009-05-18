# the contents of this file are Copyright (c) 2004-2009 Daniel Norman
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation.

package DBR::Handle;

use strict;
use base 'DBR::Common';
use DBR::Query;
use DBR::Object;
use DBR::Interface::DBRv1;
our $AUTOLOAD;

sub new {
      my( $package ) = shift;
      my %params = @_;

      my $self = {
		  dbh      => $params{dbh},
		  dbr      => $params{dbr},
		  logger   => $params{logger},
		  instance => $params{instance}
		 };

      bless( $self, $package );

      return $self->_error( 'dbh parameter is required'      ) unless $self->{dbh};
      return $self->_error( 'dbr parameter is required'      ) unless $self->{dbr};
      return $self->_error( 'instance parameter is required' ) unless $self->{instance};

      $self->{schema} = $self->{instance}->schema( dbrh => $self );
      return $self->_error( 'failed to retrieve schema' ) unless defined($self->{schema});


      my $dclass = 'DBR::Driver::' . $self->{instance}->module;
      return $self->_error("Failed to Load $dclass ($@)") unless eval "require $dclass";

      return $self->_error("Failed to create $dclass object") unless
	my $driver = $dclass->new(
				  logger => $self->{logger},
				  dbh    => $self->{dbh}
				 );

      $self->{driver} = $driver;

      # Temporary solution to interfaces
      $self->{dbrv1} = DBR::Interface::DBRv1->new(
						  logger  => $self->{logger},
						  dbrh    => $self,
						 ) or return $self->_error('failed to create DBRv1 interface object');

      return( $self );
}

sub _dbr    { $_[0]->{dbr}    }
sub _dbh    { $_[0]->{dbh}    }
sub _driver { $_[0]->{driver} }

sub select{ my $self = shift; return $self->{dbrv1}->select(@_); }
sub insert{ my $self = shift; return $self->{dbrv1}->insert(@_); }
sub update{ my $self = shift; return $self->{dbrv1}->update(@_); }
sub delete{ my $self = shift; return $self->{dbrv1}->delete(@_); }

sub _disconnect{
      my $self = shift;

      return $self->_error('dbh not found!') unless
	my $dbh = $self->{dbr}->{CACHE}->{$self->{name}}->{$self->{class}};
      delete $self->{dbr}->{CACHE}->{$self->{name}}->{$self->{class}};

      $dbh->disconnect();


      return 1;
}

sub AUTOLOAD {
      my $self = shift;
      my $method = $AUTOLOAD;

      my @params = @_;

      $method =~ s/.*:://;
      return unless $method =~ /[^A-Z]/; # skip DESTROY and all-cap methods
      return $self->_error("Cannot autoload '$method' when no schema is defined") unless $self->{schema};

      my $table = $self->{schema}->get_table( $method ) or return $self->_error("no such table '$method' exists in this schema");

      my $object = DBR::Object->new(
				    logger => $self->{logger},
				    dbrh   => $self,
				    table  => $table,
				   ) or return $self->_error('failed to create query object');

      return $object;
}

sub begin{
      my $self = shift;

      return $self->_error('Already transaction - cannot begin') if $self->{'_intran'};

      my $transcache = $self->{dbr}->{'_transcache'} ||= {};
      unless($self->{config}->{nestedtrans}){
	    if( $transcache->{$self->{name}} ){
		  #already in transaction bail out
		  $self->_logDebug('BEGIN - Fake');
		  $self->{'_faketran'} = 1;
		  $self->{'_intran'} = 1;
		  $transcache->{$self->{name}}++;
		  return 1;
	    }
      }

      $self->_logDebug('BEGIN');
      my $success = $self->{dbh}->do('BEGIN');
      return $self->_error('Failed to begin transaction') unless $success;
      $self->{'_intran'} = 1;
      $transcache->{$self->{name}}++;
      return 1;
}

sub commit{
      my $self = shift;

      my $transcache = $self->{dbr}->{'_transcache'} ||= {};
      if($self->{'_faketran'}){
	    $self->_logDebug('COMMIT - Fake');
	    $self->{'_faketran'} = 0;
	    $self->{'_intran'} = 0;
	    $transcache->{$self->{name}}--;
	    return 1;
      }

      return $self->_error('Not in transaction - cannot commit') unless $self->{'_intran'};
      $self->_logDebug('COMMIT');
      my $success = $self->{dbh}->do('COMMIT');
      return $self->_error('Failed to commit transaction') unless $success;
      $self->{'_intran'} = 0;
      $transcache->{$self->{name}}--;

      return 1;
}

sub rollback{
      my $self = shift;

      my $transcache = $self->{dbr}->{'_transcache'} ||= {};
      if($self->{'_faketran'}){
	    $self->_logDebug('ROLLBACK - Fake');
	    $self->{'_faketran'} = 0;
	    $self->{'_intran'} = 0;
	    $transcache->{$self->{name}}--;
	    #$self->{dbh}->{'AutoCommit'} = 1;
	    return 1;
      }

      return $self->_error('Not in transaction - cannot rollback') unless $self->{'_intran'};

      $self->_logDebug('ROLLBACK');
      my $success = $self->{dbh}->do('ROLLBACK');
      #$self->{dbh}->{'AutoCommit'} = 1;
      return $self->_error('Failed to roll back transaction') unless $success;
      $self->{'_intran'} = 0;
      $transcache->{$self->{name}}--;
      return 1;
}

sub DESTROY{
    my $self = shift;

    $self->rollback() if $self->{'_intran'};

}

1;