#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Mojo;
use File::Basename qw/dirname/;

BEGIN {
    $ENV{CLUSTERICIOUS_CONF_DIR} = dirname(__FILE__) . '/conf';
}

use_ok('RESTAS::Yars');

my $t = Test::Mojo->new(app => 'RESTAS::Yars');

$t->get_ok('/')->status_is(200)->content_type_like('/text\/html/')
  ->content_like(qr/welcome/i);


done_testing();
