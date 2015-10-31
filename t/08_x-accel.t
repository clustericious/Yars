use strict;
use warnings;
use Test::Clustericious::Config;
use Test::Clustericious::Cluster;
use Test::More tests => 2;
use Mojo::ByteStream qw( b );
use File::stat;

my $root;
my $t;
my $url;

subtest 'prep' => sub {
  plan tests => 4;

  $root = create_directory_ok "data";

  create_config_helper_ok data_dir => sub { $root };

  my $cluster = Test::Clustericious::Cluster->new;

  $cluster->create_cluster_ok(qw( Yars ));

  $t = $cluster->t;

  $url = $cluster->url;
};

subtest 'basic' => sub {
  plan tests => 18;

  my $content = 'Yabba Dabba Dooo!';

  my $digest = b($content)->md5_sum->to_string;

  my $file = 'fred.txt';

# Put the file

  $t->put_ok("$url/file/$file", {}, $content)
    ->status_is(201);

  my $location = $t->tx->res->headers->location;

  ok $location, "got location header";

# Get it back normally

  $t->get_ok("$url/file/$file/$digest")
    ->status_is(200)
    ->content_is($content);

  chomp (my $b64 = b(pack 'H*',$digest)->b64_encode);

  is $t->tx->res->headers->header("Content-MD5"), $b64;

  $t->get_ok("$url/file/$digest/$file")
    ->status_is(200)
    ->content_is($content);

  $t->get_ok($location)
    ->status_is(200)
    ->content_is($content);

  $t->get_ok("$url/disk/usage?count=1")
    ->status_is(200);

  is $t->tx->res->json->{$root}{count}, 1;

# Now give it the extra X-Use-X-Accel header

  $t->get_ok($location => { 'X-Use-X-Accel' => 'yes' });

  my $digest_path = '/data/' . join('/', ($digest =~ m/../g)) . "/$file";

# Should get back the X-Accel-Redirect header

  like($t->tx->res->headers->header('X-Accel-Redirect'),
       qr($digest_path$),
       "Got X-Accel-Redirect with full path");
};

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
