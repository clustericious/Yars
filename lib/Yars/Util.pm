package Yars::Util;

use strict;
use warnings;
use 5.010;
use base qw( Exporter );

our @EXPORT_OK = qw( format_tx_error );

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
