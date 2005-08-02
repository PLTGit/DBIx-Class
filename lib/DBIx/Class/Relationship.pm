package DBIx::Class::Relationship;

use strict;
use warnings;

use base qw/Class::Data::Inheritable/;

__PACKAGE__->mk_classdata('_relationships', { } );

=head1 NAME 

DBIx::Class::Relationship - Inter-table relationships

=head1 SYNOPSIS

=head1 DESCRIPTION

This class handles relationships between the tables in your database
model. It allows your to set up relationships, and to perform joins
on searches.

=head1 METHODS

=over 4

=cut

sub add_relationship {
  my ($class, $rel, $f_class, $cond, $attrs) = @_;
  die "Can't create relationship without join condition" unless $cond;
  $attrs ||= {};
  eval "use $f_class;";
  my %rels = %{ $class->_relationships };
  $rels{$rel} = { class => $f_class,
                  cond  => $cond,
                  attrs => $attrs };
  $class->_relationships(\%rels);
  #warn %{$f_class->_columns};

  return unless eval { %{$f_class->_columns}; }; # Foreign class not loaded
  my %join = (%$attrs, _action => 'join',
    _aliases => { 'self' => 'me', 'foreign' => $rel },
    _classes => { 'me' => $class, $rel => $f_class });
  eval { $class->_cond_resolve($cond, \%join) };

  if ($@) { # If the resolve failed, back out and re-throw the error
    delete $rels{$rel}; # 
    $class->_relationships(\%rels);
    $class->throw("Error creating relationship $rel: $@");
  }
  1;
}

sub _cond_key {
  my ($self, $attrs, $key) = @_;
  my $action = $attrs->{_action} || '';
  if ($action eq 'convert') {
    unless ($key =~ s/^foreign\.//) {
      $self->throw("Unable to convert relationship to WHERE clause: invalid key ${key}");
    }
    return $key;
  } elsif ($action eq 'join') {
    my ($type, $field) = split(/\./, $key);
    if (my $alias = $attrs->{_aliases}{$type}) {
      my $class = $attrs->{_classes}{$alias};
      $self->throw("Unknown column $field on $class as $alias")
        unless exists $class->_columns->{$field};
      return join('.', $alias, $field);
    } else {
      $self->throw( "Unable to resolve type ${type}: only have aliases for ".
            join(', ', keys %{$attrs->{_aliases} || {}}) );
    }
  }
  return $self->NEXT::ACTUAL::_cond_key($attrs, $key);
}

sub _cond_value {
  my ($self, $attrs, $key, $value) = @_;
  my $action = $attrs->{_action} || '';
  if ($action eq 'convert') {
    unless ($value =~ s/^self\.//) {
      $self->throw( "Unable to convert relationship to WHERE clause: invalid value ${value}" );
    }
    unless ($self->_columns->{$value}) {
      $self->throw( "Unable to convert relationship to WHERE clause: no such accessor ${value}" );
    }
    push(@{$attrs->{bind}}, $self->get_column($value));
    return '?';
  } elsif ($action eq 'join') {
    my ($type, $field) = split(/\./, $value);
    if (my $alias = $attrs->{_aliases}{$type}) {
      my $class = $attrs->{_classes}{$alias};
      $self->throw("Unknown column $field on $class as $alias")
        unless exists $class->_columns->{$field};
      return join('.', $alias, $field);
    } else {
      $self->throw( "Unable to resolve type ${type}: only have aliases for ".
            join(', ', keys %{$attrs->{_aliases} || {}}) );
    }
  }
      
  return $self->NEXT::ACTUAL::_cond_value($attrs, $key, $value)
}

sub search_related {
  my $self = shift;
  my $rel = shift;
  my $attrs = { };
  if (@_ > 1 && ref $_[$#_] eq 'HASH') {
    $attrs = { %{ pop(@_) } };
  }
  my $rel_obj = $self->_relationships->{$rel};
  $self->throw( "No such relationship ${rel}" ) unless $rel;
  $attrs = { %{$rel_obj->{attrs} || {}}, %{$attrs || {}} };
  my $s_cond;
  if (@_) {
    $self->throw( "Invalid query: @_" ) if (@_ > 1 && (@_ % 2 == 1));
    my $query = ((@_ > 1) ? {@_} : shift);
    $s_cond = $self->_cond_resolve($query, $attrs);
  }
  $attrs->{_action} = 'convert';
  my ($cond) = $self->_cond_resolve($rel_obj->{cond}, $attrs);
  $cond = "${s_cond} AND ${cond}" if $s_cond;
  return $rel_obj->{class}->retrieve_from_sql($cond, @{$attrs->{bind} || []},
                                                $attrs);
}

sub create_related {
  my ($self, $rel, $values, $attrs) = @_;
  $self->throw( "Can't call create_related as class method" ) 
    unless ref $self;
  $self->throw( "create_related needs a hash" ) 
    unless (ref $values eq 'HASH');
  my $rel_obj = $self->_relationships->{$rel};
  $self->throw( "No such relationship ${rel}" ) unless $rel;
  $self->throw( "Can't abstract implicit create for ${rel}, condition not a hash" )
    unless ref $rel_obj->{cond} eq 'HASH';
  $attrs = { %{$rel_obj->{attrs}}, %{$attrs || {}}, _action => 'convert' };
  my %fields = %$values;
  while (my ($k, $v) = each %{$rel_obj->{cond}}) {
    $self->_cond_value($attrs, $k => $v);
    $fields{$self->_cond_key($attrs, $k)} = (@{delete $attrs->{bind}})[0];
  }
  return $rel_obj->{class}->create(\%fields);
}

1;

=back

=head1 AUTHORS

Matt S. Trout <perl-stuff@trout.me.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

