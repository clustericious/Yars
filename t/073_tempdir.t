use strict;
use warnings;
use Test::More tests => 13;
use Test::Mojo;
use Test::Clustericious::Config;
use Mojo::UserAgent;
use Yars;
use Mojo::ByteStream qw( b );

my $home = home_directory_ok;

# max size should be smaller than the file
# PUT / GET messages, but larger than the 
# status, etc. messages in this test
# 100 was good enough on twin, but not acpsdev2
# 200 was good on acpsdev2, went with 500
# to be sure
$ENV{MOJO_MAX_MEMORY_SIZE} = 500; # force temp files
$ENV{MOJO_TMPDIR} = "$home/nosuchdir";

my $t = Test::Mojo->new;
$t->ua(do {

  my $ua = Mojo::UserAgent->new;
  my $data_root = create_directory_ok 'data';
  my $client_tmp = create_directory_ok 'tmp';
  
  $ua->on(start => sub {
    my($ua, $tx) = @_;
    $tx->req->content->asset->auto_upgrade(0);
  });

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
