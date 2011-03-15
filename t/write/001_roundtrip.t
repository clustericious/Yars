#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Mojo;
use Mojo::ByteStream qw/b/;
use FindBin qw/$Bin/;

use_ok('RESTAS::Yars');

my $t = Test::Mojo->new(app => 'RESTAS::Yars');


my $content = 'Yabba Dabba Dooo!';

$t->put_ok('/file/fred', {}, $content)->status_is(201);
my $digest = b($content)->md5_sum->to_string;


$t->get_ok("/file/fred/$digest")->status_is(200)->content_like(qr/Yabba/);


$t->delete_ok("/file/fred/$digest")->status_is(200);


done_testing();
