use strict;
use warnings;
use Test::Clustericious::Config;
use Test::Clustericious::Cluster;
use AnyEvent::Open3::Simple;
use Yars::Command::yars_exercise;
use Test::More tests => 13;

my $datadir = create_directory_ok 'data';
create_config_helper_ok data_dir => sub { $datadir };

my $cluster = Test::Clustericious::Cluster->new;
$cluster->create_cluster_ok('Yars');
my $t = $cluster->t;

create_config_ok Yars => { url => "$cluster->{url}" };

my $done = AnyEvent->condvar;

my $stdout = '';
my $stderr = '';
my ($exit_value, $signal);

my $ipc = AnyEvent::Open3::Simple->new(
    on_stdout => sub { $stdout .= "$_[1]\n" },
    on_stderr => sub { $stderr .= "$_[1]\n" },
    on_exit   => sub { $exit_value = $_[1]; $signal = $_[2]; $done->send; },
    on_error  => sub { BAIL_OUT $_[0]; $done->send; }
);

$ipc->run($^X, '-MYars::Command::yars_exercise', '-e',
          'Yars::Command::yars_exercise::main(qw(-n 2 -f 10 -s 8192 -g 10))');

$done->recv;

diag $stderr;
diag $stdout;

is $exit_value, 0, "exit value";
is $signal, 0, "signal";

like $stdout, qr/PUT ok 20/, "PUT 20 files";
like $stdout, qr/GET ok 200/, "GET 200 files";
like $stdout, qr/DELETE 1 20/, "DELETE 20 files";

# See if cluster is empty of all the files we PUT, then DELETEed
$t->get_ok("$cluster->{url}/bucket/usage")
  ->status_is(200);

is_deeply $t->tx->res->json->{'used'}, { $datadir => [] };

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

State_file: <%= create_directory_ok("state") . "/state.txt" %>

