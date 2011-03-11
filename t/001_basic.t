#!/usr/bin/env perl

use strict;
use warnings;

use Test::MBD '-autostart';
use Test::More tests => 9;
use Test::Mojo;

use_ok('RESTAS::Yars');

my $t = Test::Mojo->new(app => 'RESTAS::Yars');

$t->get_ok('/')->status_is(200)->content_type_is('text/html')
  ->content_like(qr/welcome/i);


$t->post_ok('/clustericious', { "Content-Type" => "application/json" },
          qq[{ "app": "RESTAS::Yars", "version" : "$RESTAS::Yars::VERSION" }])
        ->status_is(200, "posted version");

$t->get_ok('/clustericious/RESTAS::Yars')
  ->json_content_is( { app => "RESTAS::Yars", version => $RESTAS::Yars::VERSION }, "DB version is $RESTAS::Yars::VERSION " );
