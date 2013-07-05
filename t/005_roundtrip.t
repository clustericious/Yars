use strict;
use warnings;
use Test::Clustericious::Config;
use Test::Clustericious::Cluster;
use Test::More tests => 59;
use Mojo::ByteStream qw( b );

my $root = create_directory_ok "data";
create_config_helper_ok data_dir => sub { $root };

my $cluster = Test::Clustericious::Cluster->new;
$cluster->create_cluster_ok(qw( Yars ));
my $t = $cluster->t;
my $url = $cluster->url;

{
    my $content = 'Yabba Dabba Dooo!';
    my $digest = b($content)->md5_sum->to_string;
    my $file = 'fred.txt';

    $t->put_ok("$url/file/$file", {}, $content)->status_is(201);
    my $location = $t->tx->res->headers->location;
    ok $location, "got location header";
    $t->get_ok("$url/file/$file/$digest")->status_is(200)->content_is($content);
    chomp (my $b64 = b(pack 'H*',$digest)->b64_encode);
    is $t->tx->res->headers->header("Content-MD5"), $b64;
    $t->get_ok("$url/file/$digest/$file")->status_is(200)->content_is($content);
    $t->get_ok($location)->status_is(200)->content_is($content);
    is $t->get_ok("$url/disk/usage?count=1")->status_is(200)->tx->res->json->{$root}{count}, 1;

    # Idempotent PUT
    $t->put_ok("$url/file/$file", {}, $content)->status_is(200);
    my $location2 = $t->tx->res->headers->location;
    is $location, $location2, "same location header";
    is $t->get_ok("$url/disk/usage?count=1")->status_is(200)->tx->res->json->{$root}{count}, 1;
    $t->head_ok($location)->status_is(200);
    is $t->tx->res->headers->content_length, b($content)->size, "Right content-length in HEAD";
    is $t->tx->res->headers->content_type, "text/plain", "Right content-type in HEAD";
    ok $t->tx->res->headers->last_modified, "last-modified is set";
    $t->delete_ok("$url/file/$file/$digest")->status_is(200);
}

{
    # Same filename, different content
    my $nyc = $t->put_ok("$url/file/houston", {}, "a street in nyc")->status_is(201)->tx->res->headers->location;
    my $tx = $t->put_ok("$url/file/houston", {}, "we have a problem")->status_is(201)->tx->res->headers->location;
    ok $nyc ne $tx, "Two locations";
    $t->get_ok($nyc)->content_is("a street in nyc");
    $t->get_ok($tx)->content_is("we have a problem");
    $t->delete_ok($nyc);
    $t->delete_ok($tx);
}

{
    # Same content, different filename
    my $content = "sugar filled soft drink that is bad for your teeth";
    my $md5 = b($content)->md5_sum;
    my $coke = $t->put_ok("$url/file/coke", {}, $content)->status_is(201)->tx->res->headers->location;
    my $pepsi = $t->put_ok("$url/file/pepsi", {}, $content)->status_is(201)->tx->res->headers->location;
    ok $coke ne $pepsi, "Two locations";
    $t->get_ok($coke)->content_is($content);
    $t->get_ok($pepsi)->content_is($content);
    my $coke_file = join '/', $root, ($md5 =~ /(..)/g), 'coke';
    ok -e $coke_file, "wrote $coke_file";
    my $pepsi_file = join '/', $root, ($md5 =~ /(..)/g), 'pepsi';
    ok -e $pepsi_file, "wrote $pepsi_file";
    my @coke = split / /, `ls -i $coke_file`;
    my @pepsi = split / /, `ls -i $pepsi_file`;
    like $coke[0], qr/\d+/, "found inode number $coke[0]";
    is $coke[0],$pepsi[0], 'inode numbers are the same';
    $t->delete_ok($coke);
    $t->delete_ok($pepsi);
}

__DATA__

@@ etc/Yars.conf
---
% use Test::Clustericious::Config;
url: <%= cluster->url %>
servers:
  - url: <%= cluster->url %>
    disks:
      - root: <%= data_dir %>
        buckets: [ 0,1,2,3,4,5,6,7,8,9,'a','b','c','d','e','f' ]

state_file: <%= create_directory_ok("state") . "/state.txt" %>
