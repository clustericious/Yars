use strict;
use warnings;
use v5.10;
use Test::More tests => 14;
use Test::Mojo;
use Test::Clustericious::Config;
use Mojo::UserAgent;
use Mojo::IOLoop;
use Yars;
use Yars::Client;
use YAML::XS qw( Dump );

home_directory_ok;

my $config = { servers => [] };
my @data   = map { create_directory_ok "data$_" } 1..4;
my $tmp    = create_directory_ok 'tmp';

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

foreach my $index (0..1)
{
  $config->{url} = "$url[$index]";
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

$t->get_ok("$url[0]/status")
  ->status_is(200)
  ->json_is('/app_name', 'Yars');
$t->get_ok("$url[1]/status")
  ->status_is(200)
  ->json_is('/app_name', 'Yars');


# FIXME: remove all the crazy globals
#        so that we can PUT/GET files
