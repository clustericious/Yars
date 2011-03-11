package RESTAS::Yars;

=head1 NAME

RESTAS::Yars - RESTAS Yars (Yet Another RESTAS Server)

=head1 SYNOPSIS

RESTAS::Yars

=head1 DESCRIPTION

=cut

use strict;
use warnings;

use base 'Clustericious::App';
use RESTAS::Yars::Routes;

our $VERSION = '0.01';

1;
