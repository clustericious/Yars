use strict;
use warnings;
use Test::More tests => 12;
use Test::Mojo;
use Test::Clustericious::Config;
use Mojo::UserAgent;
use Yars;
use Mojo::ByteStream qw( b );

my $home = home_directory_ok;

$ENV{MOJO_MAX_MEMORY_SIZE} = 100; # force temp files
$ENV{MOJO_TMPDIR} = "$home/nosuchdir";

my $t = Test::Mojo->new;
$t->ua(do {

  my $ua = Mojo::UserAgent->new;
  my $data_root = create_directory_ok 'data';

  create_config_ok 'Yars', {
    url => $ua->app_url,

    servers => [ {
      url   => $ua->app_url,
      disks => [ {
        root => $data_root,
        buckets => [ '0'..'9', 'A'..'Z' ],
      } ],
    } ],
  };

  $ua->app(Yars->new);

  $ua;
});

$t->get_ok('/status')
  ->json_is('/app_name', 'Yars');

my $url = $t->ua->app_url->to_string;
$url =~ s{/$}{};

my $content = 'x' x 1_000_000;
my $digest = b($content)->md5_sum->to_string;
my $filename = 'stuff.txt';

chomp(my $b64 = b($content)->md5_bytes->b64_encode);

$t->put_ok("$url/file/$filename", { "Content-MD5" => $b64 }, $content)
  ->status_is(201)
  ->header_like('Location', qr[.*$digest.*]);

$ENV{MOJO_TMPDIR} = create_directory_ok 'tmp';

$t->get_ok("$url/file/$filename/$digest")
  ->status_is(200);

is length($t->tx->res->body), length($content), "content lengths match";
