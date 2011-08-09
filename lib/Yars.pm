package Yars;

=head1 NAME

Yars (Yet Another RESTAS Server)

=cut

use strict;
use warnings;
use base 'Clustericious::App';
use Yars::Routes;
use Yars::Balancer;
our $VERSION = '0.21';

__PACKAGE__->attr( secret => q[rQJzFpwh,ZY;+9dq293.xj6tc?1.oa+a4r/90tCAV] );

sub startup {
    my $self = shift;
    $self->SUPER::startup(@_);
    Yars::Balancer->new(app => $self)->init_and_start;
}

1;
