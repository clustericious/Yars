#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Mojo;
use File::Temp;
use Yars;

my $t = Test::Mojo->new('Yars');
$t->app->config->servers(
    default => [{
        disks => [ { root => File::Temp->newdir, buckets => [ '0' .. '9', 'A' .. 'F' ] } ]
    }]
);
$t->app->config->{url} = $t->ua->app_url;
$t->app->config->servers->[0]{url} = $t->app->config->{url};

my $content = 'We\'re gonna be late for the lodge meeting Fred.';

$t->get_ok("/file/barney/5551212", {}, $content)->status_is(404);


done_testing();
