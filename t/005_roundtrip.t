#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Mojo;
use Mojo::ByteStream qw/b/;
use File::Temp;
use Yars;

my $t = Test::Mojo->new('Yars');
my $root = File::Temp->newdir(CLEANUP => 1);
$t->app->config->servers(
    default => [{
        disks => [ { root => $root, buckets => [ '0' .. '9', 'A' .. 'F' ] } ]
    }]
);
$t->app->config->{url} = $t->ua->test_server;
$t->app->config->servers->[0]{url} = $t->app->config->{url};

my $content = 'Yabba Dabba Dooo!';
my $digest = b($content)->md5_sum->to_string;

my $file = 'fred.txt';

$t->put_ok("/file/$file", {}, $content)->status_is(201);
my $location = $t->tx->res->headers->location;
ok $location, "got location header";
$t->get_ok("/file/$file/$digest")->status_is(200)->content_is($content);
is $t->tx->res->headers->header("Content-MD5"),b(pack 'H*',$digest)->b64_encode;
$t->get_ok("/file/$digest/$file")->status_is(200)->content_is($content);
$t->get_ok($location)->status_is(200)->content_is($content);
is $t->get_ok("/disk/usage?count=1")->status_is(200)->tx->res->json->{$root}{count}, 1;

# Idempotent PUT
$t->put_ok("/file/$file", {}, $content)->status_is(200);
my $location2 = $t->tx->res->headers->location;
is $location, $location2, "same location header";
is $t->get_ok("/disk/usage?count=1")->status_is(200)->tx->res->json->{$root}{count}, 1;
$t->head_ok($location)->status_is(200);
is $t->tx->res->headers->content_length, b($content)->size, "Right content-length in HEAD";
is $t->tx->res->headers->content_type, "text/plain", "Right content-type in HEAD";
ok $t->tx->res->headers->last_modified, "last-modified is set";
$t->delete_ok("/file/$file/$digest")->status_is(200);

# Same filename, different content
my $nyc = $t->put_ok("/file/houston", {}, "a street in nyc")->status_is(201)->tx->res->headers->location;
my $tx = $t->put_ok("/file/houston", {}, "we have a problem")->status_is(201)->tx->res->headers->location;
ok $nyc ne $tx, "Two locations";
$t->get_ok($nyc)->content_is("a street in nyc");
$t->get_ok($tx)->content_is("we have a problem");
$t->delete_ok($nyc);
$t->delete_ok($tx);

done_testing();
