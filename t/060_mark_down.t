use strict;
use warnings;
use FindBin ();
BEGIN { require "$FindBin::Bin/etc/legacy.pl" }

use File::HomeDir::Test;
use Test::More tests => 72;
use Test::Mojo;
use File::Path qw/mkpath/;
use File::Basename qw/dirname/;
use Mojo::ByteStream qw/b/;
use File::Temp;
use Yars;

my $test_files = 20;
my $root = File::Temp->newdir(CLEANUP => 1);

$ENV{LOG_LEVEL} = "WARN";

my $t = Test::Mojo->new("Yars");

sub _mark_down {
    my $t = shift;
    my $which = shift;
    $t->post_ok("/disk/status",
        { "Content-Type" => "application/json" },
        Mojo::JSON->new->encode( { root => "$root/$which", "state" => "down" }))
               ->status_is(200)
               ->content_like(qr/ok/);
}

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
my $temp = File::Temp->new;
my $tempdir = File::Temp->newdir;
$conf->{state_file} = "$tempdir/state.txt";

$t->get_ok('/'."got /");

$t->get_ok('/servers/status')->status_is(200)->json_is('',
    {
        "http://localhost:9050" =>
          { map {( "$root/$_" => "up" )} qw/one two three four five/ }
    }
);

_mark_down($t,"two");
_mark_down($t,"three");
mkpath "$root/four";
chmod 0555, "$root/four";

$t->get_ok('/servers/status')->status_is(200)->json_is('',
    {
        "http://localhost:9050" =>
          {
            (map {( "$root/$_" => "up" )} qw/one five/),
            (map {( "$root/$_" => "down" )} qw/two three four/)
          }
    }
);

_mark_down($t,"five");


my ($one,$two) = (0,0);
for my $i (1..$test_files) {
    my $content = "content $i";
    $t->put_ok("/file/filename_$i", {}, $content)->status_is(201);
    for (b($content)->md5_sum) {
         /^[0-3]/i and $one++;
         /^[4-7]/i and $two++;
     }
}

TODO: {
    local $TODO = "run yars_fast_balance";
    my $json = $t->get_ok("/disk/usage?count=1")->status_is(200)->tx->res->json;
    is $json->{"$root/one"}{count}, $test_files;
    is $json->{"$root/$_"}{count}, 0 for qw/two three four five/;

    my $remaining = int($test_files - $two);
    $json = $t->get_ok("/disk/usage?count=1")->status_is(200)->tx->res->json;
    is $json->{"$root/one"}{count}, $remaining;
    is $json->{"$root/two"}{count}, $two;
    is $json->{"$root/$_"}{count}, 0 for qw/three four five/;

    # Ensure an invalid host causes an exception, not a request loop
    $t->post_ok("/disk/status",
        { "Content-Type" => "application/json" },
        Mojo::JSON->new->encode( { server => "http://101.010.0.0", root => "foo/bar", "state" => "up" }))
               ->status_is(400);
}


