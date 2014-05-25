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

sub _index_info {
    my ($self, $inst, $tbl) = @_;

    local $self->{dbh}->{RaiseError} = 1;
    return $self->{dbh}->selectall_arrayref(q{
        SELECT TABLE_NAME, INDEX_NAME, NON_UNIQUE, COLUMN_NAME, SUB_PART FROM INFORMATION_SCHEMA.STATISTICS
        WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND INDEX_NAME <> 'PRIMARY' ORDER BY INDEX_NAME, SEQ_IN_INDEX
    }, { Slice => { } }, $inst->database, $tbl);
}

sub _fk_info {
    my ($self, $inst, $tbl) = @_;

    local $self->{dbh}->{RaiseError} = 1;
    return $self->{dbh}->selectall_arrayref(q{
        SELECT TABLE_NAME, COLUMN_NAME, REFERENCED_TABLE_SCHEMA, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
        WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND REFERENCED_TABLE_NAME IS NOT NULL AND ORDINAL_POSITION = 1
    }, { Slice => { } }, $inst->database, $tbl);
}

sub _column_info {
    my $self = shift;
    my $list = $self->SUPER::_column_info(@_);
    map { $_->{UNSIGNED} = 1 if $_->{mysql_type_name} =~ / unsigned/i } @$list;
    $list;
}

1;
