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
use File::Basename qw/dirname/;
use Mojo::ByteStream qw/b/;

sub _touch {
    my $path = shift;
    mkpath dirname($path);
    open my $fp, ">>$path" or die "could not touch $path : $!";
    close $fp;
    return 1;
}

my $t = Test::Mojo->new("Yars");
my $conf = $t->app->config;
$conf->servers( default => [{
            url   => "http://localhost:9050",
            disks => [
                { root => "$root/one",   buckets => [ qw/0 1 2 3/ ] },
                { root => "$root/two",   buckets => [ qw/4 5 6 7/ ] },
                { root => "$root/three", buckets => [ qw/8 9 A B/ ] },
                { root => "$root/four",  buckets => [ qw/C D/ ] },
                { root => "$root/five",  buckets => [ qw/E F/ ] },
            ]
        }
    ]);
$conf->{url} = "http://localhost:9050"; # TODO provide a better config api

$t->get_ok('/'."got /");

_touch "$root/two.is_down";
_touch "$root/three/is_down";
mkpath "$root/four";
chmod 0555, "$root/four";

$t->post_ok("/disk/status$root/five",
    { "Content-Type" => "application/json" },
    Mojo::JSON->new->encode( { "state" => "down" }))
           ->status_is(200)
           ->content_like(qr/ok/);

for my $i (1..$test_files) {
    my $content = "content $i";
    $t->put_ok("/file/filename_$i", {}, $content)->status_is(201);
}

$t->get_ok("/stats/files_by_disk?count=1&df=0")->status_is(200)
  ->json_content_is( { "$root/one"   => { count => $test_files },
                       "$root/two"   => { count => 0 },
                       "$root/three" => { count => 0 },
                       "$root/four"  => { count => 0 },
                       "$root/five"  => { count => 0 },
                       });

done_testing();

