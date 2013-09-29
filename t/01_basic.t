use strict;
use warnings;
use Test::Clustericious::Cluster;
use Test::More tests => 7;

my $cluster = Test::Clustericious::Cluster->new;
$cluster->create_cluster_ok(qw( Yars ));

my $t = $cluster->t;

$t->get_ok($cluster->url)
  ->status_is(200)
  ->content_type_like('/text\/html/')
  ->content_like(qr/welcome/i);

__DATA__

@@ etc/Yars.conf
---
% use Test::Clustericious::Config;
url: <%= cluster->url %>
servers:
  - url: <%= cluster->url %>
    disks:
      - root: <%= create_directory_ok "data" %>
        buckets: [ 0,1,2,3,4,5,6,7,8,9,'a','b','c','d','e','f' ]

state_file: <%= create_directory_ok("state") . "/state.txt" %>