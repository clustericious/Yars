package Yars;

=head1 NAME

Yars (Yet Another RESTAS Server)

=cut

use strict;
use warnings;
use base 'Clustericious::App';
use Yars::Routes;
our $VERSION = '0.19';

__PACKAGE__->attr( secret => q[rQJzFpwh,ZY;+9dq293.xj6tc?1.oa+a4r/90tCAV] );

1;
