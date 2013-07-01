use strict;
use warnings;
use v5.10;
use Test::More tests => 27;
use Test::Mojo;
use Test::Clustericious::Config;
use Mojo::UserAgent;
use Mojo::IOLoop;
use Yars;
use Yars::Client;
use YAML::XS qw( Dump );

my $config   = { servers => [] };
my @data     = map { create_directory_ok "data_$_" } 1..4;
my $upload   = create_directory_ok 'up';
my $download = create_directory_ok 'dl';

my $loop = Mojo::IOLoop->new;
my @url = map { 
  my $url = Mojo::URL->new("http://127.0.0.1");
  $url->port($loop->generate_port);
  $url } (1..2);

push @{ $config->{servers} }, {
  url => "$url[0]",
  disks => [
    { root => $data[0], buckets => [ 0..3 ] },
    { root => $data[1], buckets => [ 4..7 ] },
  ]
};

push @{ $config->{servers} }, {
  url => "$url[1]",
  disks => [
    { root => $data[2], buckets => [ 8..9, 'a'..'b' ] },
    { root => $data[3], buckets => [ 'c'..'f' ] },
  ]
};

my $t = Test::Mojo->new;
$t->ua(Mojo::UserAgent->new(ioloop => $loop));

my $state = create_directory_ok "state";

foreach my $index (0..1)
{
  $config->{url} = "$url[$index]";
  $config->{state_file} = "$state/$index.txt";
   
  create_config_ok 'Yars', $config;
  #note Dump($config);

  state $keepers = [];
  my $server = Mojo::Server::Daemon->new(
    ioloop => $loop, 
    silent => 1,
  );
  $server->listen(["$url[$index]"]);
  $server->app(Yars->new);
  $server->start;
  
  push @$keepers, $server;
}

$t->get_ok("$url[0]/")
  ->status_is(200)
  ->content_type_like(qr{text/html})
  ->content_like(qr{welcome}i);

$t->get_ok("$url[0]/status")
  ->status_is(200)
  ->json_is('/app_name', 'Yars');
$t->get_ok("$url[1]/status")
  ->status_is(200)
  ->json_is('/app_name', 'Yars');

my $client = Yars::Client->new;
$client->client($t->ua);

# first file hello.txt is generated to go to the first Yars server ($url[0])
do {
  use autodie;
  open my $fh, '>', "$upload/hello.txt";
  print $fh 'hello world';
  close $fh;
};

ok $client->upload("$upload/hello.txt"), 'upload hello.txt';
ok $client->download("hello.txt", '5eb63bbbe01eeed093cb22bb8f5acdc3', $download), 'download hello.txt';
ok -r "$download/hello.txt", "file downloaded to correct location";

do {
  use autodie;
  open my $fh, '<', "$download/hello.txt";
  my $data = <$fh>;
  close $fh;
  
  is $data, 'hello world', 'file has correct content';
};


# second file second.txt is generated to go to the second Yars server ($url[1])
do {
  use autodie;
  open my $fh, '>', "$upload/second.txt";
  print $fh "and again \n";
  close $fh;
};

ok $client->upload("$upload/second.txt"), "upload second.txt";
ok $client->download("second.txt", 'b571a4c57d27b581da89285fc6fe9e74', $download), "download second.txt";
ok -r "$download/second.txt", "file downloaded to correct location";

do {
  use autodie;
  open my $fh, '<', "$download/second.txt";
  my $data = <$fh>;
  close $fh;
  
  is $data, "and again \n", 'file has correct content';
};
