package RESTAS::Yars::Routes;

=head1 NAME

RESTAS::Yars::Routes -- set up the routes for RESTAS::Yars.

=head1 DESCRIPTION

This package creates all the routes, and thus defines
the API for RESTAS::Yars.

=cut

use strict;
use warnings;

use Clustericious::RouteBuilder;

get    '/'              => sub {shift->
                                render_text("welcome to RESTAS::Yars")};
post   '/:items/search' => \&do_search;
get    '/:items/search' => \&do_search;
1;
