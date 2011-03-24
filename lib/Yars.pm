package Yars;

=head1 NAME

Yars (Yet Another RESTAS Server)

=head1 SYNOPSIS

Yars

=head1 DESCRIPTION

=cut

use strict;
use warnings;
use base 'Clustericious::App';
use Yars::Routes;
our $VERSION = '0.14';

__PACKAGE__->attr( secret => q[rQJzFpwh,ZY;+9dq293.xj6tc?1.oa+a4r/90tCAV] );

1;
