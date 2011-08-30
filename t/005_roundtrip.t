#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Mojo;
use Mojo::ByteStream qw/b/;
use FindBin qw/$Bin/;
use Yars;

my $t = Test::Mojo->new('Yars');


my $file = 'fred.txt';
my $content = 'Yabba Dabba Dooo!';
my $digest = b($content)->md5_sum->to_string;

$t->put_ok("/file/$file", {}, $content)->status_is(201);
$t->put_ok("/file/$file", {}, $content)->status_is(200);  # idempotent putting

my $location = $t->tx->res->headers->location;
$t->get_ok("/file/$file/$digest")->status_is(200)->content_is($content);
$t->get_ok("/file/$digest/$file")->status_is(200)->content_is($content);
$t->get_ok($location)->status_is(200)->content_is($content);
$t->delete_ok("/file/$file/$digest")->status_is(200);


done_testing();
