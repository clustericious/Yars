#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Mojo;
use Mojo::ByteStream qw/b/;
use File::Temp;
use Yars;

$ENV{MOJO_MAX_MEMORY_SIZE} = 1; # Force temp files.
$ENV{MOJO_TMPDIR} = "/dev/null"; # should be computed during request

my $t = Test::Mojo->new('Yars');
my $root = File::Temp->newdir(CLEANUP => 1);
$t->app->config->servers(
    default => [{
        disks => [ { root => $root, buckets => [ '0' .. '9', 'A' .. 'F' ] } ]
    }]
);
$t->app->config->{url} = $t->ua->test_server;
$t->app->config->servers->[0]{url} = $t->app->config->{url};

my $content = 'x' x 1_000_000;
my $digest = b($content)->md5_sum->to_string;
my $filename = 'stuff.txt';

$t->get_ok("/")->content_is("welcome to Yars"); # also reads config.

$t->put_ok("/file/$filename", {"Content-MD5" => $digest}, $content)->status_is(201);

my $location = $t->tx->res->headers->location;
ok $location, "got location header";

$ENV{MOJO_TMPDIR} = "/tmp";
my $got = $t->get_ok("/file/$filename/$digest")->status_is(200)->tx->success->body;

ok $got eq $content, "got content";
is $t->tx->res->headers->header("Content-MD5"),$digest;

$t->delete_ok("/file/$filename/$digest")->status_is(200);

done_testing();
