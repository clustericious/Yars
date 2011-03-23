#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Mojo;
use Mojo::ByteStream qw/b/;
use Yars;

my $t = Test::Mojo->new(app => 'Yars');

my $content = 'Yabba Dabba Dooo!';
my $digest = b($content)->md5_sum->to_string;
my $bad_digest = '5551212';


$t->put_ok("/file/fred/$digest", {}, $content)->status_is(201);

$t->put_ok("/file/fred/$bad_digest", {}, $content)->status_is(400);


done_testing();
