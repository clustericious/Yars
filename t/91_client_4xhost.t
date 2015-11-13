use strict;
use warnings;
use 5.010;
use Test::Clustericious::Config;
use Test::Clustericious::Cluster;
use Test::More;
use Yars::Client;
use Path::Class qw( file dir );
use Clustericious::Config;
use File::Temp qw( tempdir );
use File::HomeDir;
use File::Path qw( remove_tree );

plan tests => 3;

my $cluster = Test::Clustericious::Cluster->new;

subtest prep => sub {
  plan tests => 7;
  create_directory_ok 'foo1';
  create_directory_ok 'foo2';
  create_directory_ok 'foo3';
  create_directory_ok 'foo4';
  $cluster->create_cluster_ok(qw( Yars Yars Yars Yars ));
  
  #use YAML::XS;
  #use File::HomeDir;
  #use Path::Class qw( file );
  #note "~ config template ~";
  #note file(File::HomeDir->my_home, 'etc', 'Yars.conf')->slurp;
  #note "~ config data ~";
  #note YAML::XS::Dump(Clustericious::Config->new('Yars'));

  my $config = Clustericious::Config->new('Yars');
  is $config->url, $cluster->urls->[3], "primary is @{[ $cluster->urls->[3] ]}";
  is $config->failover_urls->[0], $cluster->urls->[2], "failover is @{[ $cluster->urls->[2] ]}";
  note "url:      ", $_ for map { $_->{url} } $config->servers;
};

my $ua = $cluster->t->ua;
$ua->max_redirects(3);
$_->tools->_set_ua(sub { my $ua = $cluster->create_ua; $ua }) for @{ $cluster->apps };

subtest 'stashed on non-failover, non-primary' => sub {
  plan tests => 3;

  my $data = "\x68\x65\x72\x65\x0a";
  
  my $y = Yars::Client->new;
  
  is $y->upload('stuff', \$data), 'ok', 'uploaded stuff';
  
  subtest 'not stashed' => sub {
    plan tests => 2;
    my $dest = file(tempdir( CLEANUP => 1 ), 'stuff');  
    is $y->download('stuff', 'bc98d84673286ce1447eca1766f28504', $dest->parent), 'ok', 'download is ok';
    is $dest->slurp, $data, 'download content matches';
  };
  
  # remove old
  dir(File::HomeDir->my_home, 'foo2', 'bc')->rmtree(0,0);
  # recreate as stashed file
  my $dir = dir(File::HomeDir->my_home, qw( foo1 bc 98 d8 46 73 28 6c e1 44 7e ca 17 66 f2 85 04 ));
  $dir->mkpath(0,0755);
  $dir->file('stuff')->spew($data);
  
  subtest 'stashed' => sub {
    plan tests => 2;
    my $dest = file(tempdir( CLEANUP => 1 ), 'stuff');  
    is $y->download('stuff', 'bc98d84673286ce1447eca1766f28504', $dest->parent), 'ok', 'download is ok';
    is $dest->slurp, $data, 'download content matches';
  };

  reset_store(); 
};

subtest 'bucket cache' => sub {

  my $y = Yars::Client->new;
  my $good_bucket_map = $y->bucket_map_cached;
  my $bad_bucket_map  = { map { sprintf('%x', $_) => $good_bucket_map->{sprintf '%x', ($_+4)%16} } 0..15 };
  
  subtest upload => sub {
    $y->bucket_map_cached($bad_bucket_map);
    is $y->bucket_map_cached, $bad_bucket_map, 'preload with incorrect bucket map';  
    
  };  
};

sub reset_store
{
  foreach my $dir (grep { $_->basename ne 'tmp' } map { dir($_)->children } map { $_->{root} } map { @{ $_->{disks} } } Clustericious::Config->new('Yars')->servers)
  {
    $DB::single = 1;
    remove_tree("$dir", { verbose => 0 });
  }
}

__DATA__

@@ etc/Yars.conf
---
url: <%= cluster->url %>
failover_urls:
  - <%= cluster->urls->[2] %>

servers:
  - url: <%= cluster->urls->[0] %>
    disks:
      - root: <%= dir home, 'foo1' %>
        buckets: [ c, d, e, f ]

  - url: <%= cluster->urls->[1] %>
    disks:
      - root: <%= dir home, 'foo2' %>
        buckets: [ 8, 9, a, b ]

  # failover
  - url: <%= cluster->urls->[2] %>
    disks:
      - root: <%= dir home, 'foo3' %>
        buckets: [ 4, 5, 6, 7 ]

  # primary
  - url: <%= cluster->urls->[3] %>
    disks:
      - root: <%= dir home, 'foo4' %>
        buckets: [ 0, 1, 2, 3 ]

state_file: <%= dir home, 'state' . cluster->index %>


