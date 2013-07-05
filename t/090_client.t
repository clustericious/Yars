use strict;
use warnings;
use Test::Clustericious::Config;
use Test::Clustericious::Cluster;
use Test::More tests => 16;
use Digest::file qw( digest_file_hex );
use Yars::Client;

my $cluster = Test::Clustericious::Cluster->new;
$cluster->create_cluster_ok(qw( Yars ));
my $t = $cluster->t;

my $y = Yars::Client->new;
$y->client($t->ua);

do {
  my $status = $y->status;
  is $status->{app_name}, 'Yars', 'status.app_name = Yars';
  is $status->{server_url}, $cluster->url, 'status.server_url = ' . $cluster->url;
};

my $tmp = create_directory_ok 'tmp';
my $data = "some data $$ ".time;
do {
  open my $fh, '>', "$tmp/foo";
  print $fh $data;
  close $fh;
};

ok $y->upload("$tmp/foo"), "uploading foo";
is $y->res->code, '201', 'Created';

my $md5 = digest_file_hex("$tmp/foo",'MD5');
my $content = $y->get($md5,'foo');
ok $content, "got content";
is $content, $data, "got same content";

my $download_dir = create_directory_ok 'download';
chdir $download_dir or die $!;
ok $y->download($md5,'foo'), "Downloaded foo";
ok -e 'foo', "Downloaded foo";
my $got = join "", IO::File->new("<foo")->getlines;
is $got, $data, "got same contents";
chdir(File::Spec->rootdir);

# TODO
# my $status = $y->check_manifest($filename);
# diag explain $status;

__DATA__

@@ etc/Yars.conf
---
% use Test::Clustericious::Config;
url : <%= cluster->url %>

servers :
    - url : <%= cluster->urls->[0] %>
      disks :
        - root : <%= create_directory_ok 'data' %>
          buckets : [0,1,2,3,4,5,6,7,8,9,A,B,C,D,E,F]

state_file: <%= create_directory_ok('state') . '/state' %>
