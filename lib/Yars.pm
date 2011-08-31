package Yars;

=head1 NAME

Yars (Yet Another REST Server)

=cut

use strict;
use warnings;
use base 'Clustericious::App';
use Yars::Routes;
use Yars::Balancer;
our $VERSION = '0.30';

__PACKAGE__->attr( secret => rand );

1;
