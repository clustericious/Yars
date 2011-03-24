#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Mojo;
use Mojo::ByteStream qw/b/;
use FindBin qw/$Bin/;
use Yars;

my $t = Test::Mojo->new(app => 'Yars');


my $content = 'Yabba Dabba Dooo!';
my $digest = b($content)->md5_sum->to_string;


my $file = 'fred.txt';
$t->put_ok("/file/$file", {}, $content)->status_is(201);
$t->get_ok("/file/$file/$digest")->status_is(200)->content_like(qr/Yabba/);
$t->delete_ok("/file/$file/$digest")->status_is(200);
    



done_testing();