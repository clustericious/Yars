#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Mojo;
use Mojo::ByteStream qw/b/;
use File::Temp;
use Yars;

my $t = Test::Mojo->new('Yars');
my $root = File::Temp->newdir;
$t->app->config->servers(
    default => [{
        url   => 'dummy',
        disks => [ { root => $root, buckets => [ '0' .. '9', 'A' .. 'F' ] } ]
    }]
);
$t->app->config->{url} = 'dummy';

my $content = 'Yabba Dabba Dooo!';
my $digest = b($content)->md5_sum->to_string;

my $file = 'fred.txt';

$t->put_ok("/file/$file", {}, $content)->status_is(201);
my $location = $t->tx->res->headers->location;
$t->get_ok("/file/$file/$digest")->status_is(200)->content_is($content);
$t->get_ok("/file/$digest/$file")->status_is(200)->content_is($content);
$t->get_ok($location)->status_is(200)->content_is($content);
$t->get_ok("/stats/files_by_disk?count=1&df=0")->status_is(200)->json_content_is({$root => {count => 1}});

$t->head_ok($location)->status_is(200);

$t->delete_ok("/file/$file/$digest")->status_is(200);

done_testing();
