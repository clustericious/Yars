#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Mojo;
use Mojo::ByteStream qw/b/;
use File::Temp;
use Yars;

my $t = Test::Mojo->new('Yars');
$t->app->config->servers(
    default => [{
        disks => [ { root => File::Temp->newdir, buckets => [ '0' .. '9', 'A' .. 'F' ] } ]
    }]
);
$t->app->config->{url} = $t->ua->test_server;
$t->app->config->servers->[0]{url} = $t->app->config->{url};

my $content = 'Yabba Dabba Dooo!';
my $digest = b($content)->md5_sum->to_string;
my $bad_digest = '5551212';


$t->put_ok("/file/fred/$digest", {}, $content)->status_is(201);

$t->put_ok("/file/fred/$bad_digest", {}, $content)->status_is(400);


done_testing();
