package DBR::Misc::Connection::Mysql;

use strict;
use base 'DBR::Misc::Connection';

sub new {
    my $self = shift->SUPER::new(@_);

    # enable encoding on the client.  this is in ADDITION to setting it on
    # the server, which is done by the connectstring.  Sigh.

    $self->{dbh}->{mysql_enable_utf8} = 1;
    $self;
}

sub getSequenceValue{
      my $self = shift;
      my $call = shift;

      my ($insert_id)  = $self->{dbh}->selectrow_array('select last_insert_id()');
      return $insert_id;

}

sub can_trust_execute_rowcount{ 1 } # NOTE: This should be variable when mysql_use_result is implemented

sub qualify_table {
    my $self = shift;
    my $inst = shift;
    my $table = shift;

    return $self->quote_identifier($inst->database) . '.' . $self->quote_identifier($table);
}

sub quote {
    my $self = shift;

    # MEGA HACK: the MySQL driver, with ;mysql_enable_utf8=1, doesn't like strings
    # *unless* they are *internally* coded in UTF8.  So we need to disable Perl's
    # ISO-8859-only optimization here

    ("\x{100}" x 0) . $self->{dbh}->quote(@_);
}

1;
