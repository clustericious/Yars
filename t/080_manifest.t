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

$t->app->config->{url} = $t->ua->app_url;
$t->app->config->servers->[0]{url} = $t->app->config->{url};

my $count = 2;

my @filenames = map "filename_$_", 0..$count-1;
my @contents  = map "$_"x10, 0..$count-1;
my @md5s      = map b($_)->md5_sum, @contents;

my @missing_filenames = map "filename_$_", $count..$count+5;
my @missing_contents  = map "$_"x10, $count..$count+5;
my @missing_md5s      = map b($_)->md5_sum, @missing_contents;


for (0..$count-1) {
    $t->put_ok("/file/$filenames[$_]", { }, $contents[$_])->status_is(201);
}

my $manifest = join "\n", map "$md5s[$_]  some/stuff/$filenames[$_]", 0..$count-1;
$manifest .= "\n";
$manifest .= join "\n", map "$missing_md5s[$_]  not/there/$missing_filenames[$_]", 0..5;

$t->post_ok(
    '/check/manifest?show_found=1',
    { "Content-Type" => "application/json" },
    Mojo::JSON->new->encode( { manifest => $manifest } )
)->status_is(200)
 ->json_content_is( {
    missing => [ map +{ filename => $missing_filenames[$_], md5 => $missing_md5s[$_] }, 0..5 ],
    found   => [ map +{ filename => $filenames[$_], md5 => $md5s[$_] }, 0..$count-1 ],
} );

done_testing();
