package Yars::Util;

use strict;
use warnings;
use 5.010;
use base qw( Exporter );

# ABSTRACT: Yars internally used functions.
# VERSION

our @EXPORT_OK = qw( format_tx_error );

=head1 FUNCTIONS

=head2 format_tx_error

 say format_tx_error($tx->error);

Formats a transaction error for human readable diagnostic.

=cut

sub format_tx_error
{
  my($error) = @_;
  if($error->{advice})
  {
    return sprintf("[%s] %s", $error->{advice}, $error->{message});
  }
  elsif($error->{code})
  {
    return sprintf("(%s) %s", $error->{code}, $error->{message});
  }
  $error->{message};
}

1;
