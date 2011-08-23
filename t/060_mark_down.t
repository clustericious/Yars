#!perl

# t/060_mark_down.t

use File::Temp;
use strict;
use warnings;

my $test_files = 20;
my $root = File::Temp->newdir(CLEANUP => 0);

use Test::More;
use Test::Mojo;
use File::Path qw/mkpath/;
use Mojo::ByteStream qw/b/;

my $t = Test::Mojo->new("Yars");
my $conf = $t->app->config;
$conf->servers( default => [{
            url   => "http://localhost:9050",
            disks => [
                { root => "$root/one",   buckets => [ qw/0 1 2 3/ ] },
                { root => "$root/two",   buckets => [ qw/4 5 6 7/ ] },
                { root => "$root/three", buckets => [ qw/8 9 A B/ ] },
                { root => "$root/four",  buckets => [ qw/C D E F/ ] },
            ]
        }
    ]);
$conf->{url} = "http://localhost:9050"; # TODO provide a better config api
diag "url set to ".$conf->url;

$t->get_ok('/'."got /");

{
    ok ( (open my $fp, ">$root/two.is_down"), "mark two down");
    close $fp;
}

{
    mkpath "$root/three";
    ok ( (open my $fp, ">$root/three/is_down"), "mark three down");
    close $fp;
}

mkpath "$root/four";
ok ( (chmod 0555, "$root/four"), "mark four down");

for my $i (1..$test_files) {
    my $content = "content $i";
    $t->put_ok("/file/filename_$i", {}, $content)->status_is(201);
}

$t->get_ok("/stats/files_by_disk?count=1&df=0")->status_is(200)
  ->json_content_is( { "$root/one"   => { count => $test_files },
                       "$root/two"   => { count => 0 },
                       "$root/three" => { count => 0 },
                       "$root/four"  => { count => 0 },
                       });

done_testing();

