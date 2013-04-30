use strict;
use warnings;
use FindBin ();
BEGIN { require "$FindBin::Bin/etc/setup_legacy.pl" }

use File::HomeDir::Test;
use Test::More;
use Test::Mojo;
use Mojo::ByteStream qw/b/;
use File::Temp;
use Yars;
$ENV{LOG_LEVEL} = 'FATAL';

my $t = Test::Mojo->new('Yars');
my $root = File::Temp->newdir;
$t->app->config->servers(
    default => [{
        disks => [ { root => $root, buckets => [ '0' .. '9', 'A' .. 'F' ] } ]
    }]
);
$t->app->config->{url} = $t->ua->app_url;
$t->app->config->servers->[0]{url} = $t->app->config->{url};

my $content = 'Yabba Dabba Dooo!';
my $digest = b($content)->md5_sum->to_string;
my $bad_digest = '5551212';


$t->put_ok("/file/fred/$digest", {}, $content)->status_is(201);
my $location = $t->tx->res->headers->location;
$t->put_ok("/file/fred/$bad_digest", {}, $content)->status_is(400);

$t->get_ok($location)->content_is($content);

# Corrupt it
my $filename = join '/', $root, grep length, (split /(..)/,$digest),'fred';
ok -e $filename, "found file on filesystem";
open my $fp, ">$filename" or die "can't write to $root/$filename : $!";
ok ( (print $fp "drink more coffee"), "wrote more data to file");
close $fp or die $!;

$t->get_ok($location)->status_isnt(200);

done_testing();
