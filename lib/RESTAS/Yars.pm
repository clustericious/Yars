package RESTAS::Yars;

=head1 NAME

RESTAS::Yars (Yet Another RESTAS Server)

=head1 SYNOPSIS

RESTAS::Yars

=head1 DESCRIPTION

=cut

use strict;
use warnings;
use base 'Clustericious::App';
use RESTAS::Yars::Routes;
our $VERSION = '0.01';

__PACKAGE__->attr( secret => q[rQJzFpwh,ZY;+9dq293.xj6tc?1.oa+a4r/90tCAV] );

1;
