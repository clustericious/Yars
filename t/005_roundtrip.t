#!/usr/bin/env perl

use strict;
use warnings;

BEGIN {
    use File::Basename qw/dirname/;
    $ENV{CLUSTERICIOUS_CONF_DIR} = dirname(__FILE__).'/conf';
}

use Test::More;
use Test::Mojo;
use Mojo::ByteStream qw/b/;
use FindBin qw/$Bin/;
use Yars;

my $t = Test::Mojo->new('Yars');

my $content = 'Yabba Dabba Dooo!';
my $digest = b($content)->md5_sum->to_string;

my $file = 'fred.txt';

$t->put_ok("/file/$file", {}, $content)->status_is(201);
my $location = $t->tx->res->headers->location;
$t->get_ok("/file/$file/$digest")->status_is(200)->content_is($content);
$t->get_ok("/file/$digest/$file")->status_is(200)->content_is($content);
$t->get_ok($location)->status_is(200)->content_is($content);

$t->delete_ok("/file/$file/$digest")->status_is(200);

done_testing();
