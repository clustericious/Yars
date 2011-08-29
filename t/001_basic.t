#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Mojo;
use File::Temp;
use_ok('Yars');

my $root = File::Temp->newdir(CLEANUP => 1);

my $t = Test::Mojo->new('Yars');
$t->app->config->servers(
    default => [{
        url   => 'dummy',
        disks => [ { root => $root, buckets => [ '0' .. '9', 'A' .. 'F' ] } ]
    }]
);
$t->app->config->{url} = 'dummy';

$t->get_ok('/')->status_is(200)->content_type_like('/text\/html/')
  ->content_like(qr/welcome/i);


done_testing();
