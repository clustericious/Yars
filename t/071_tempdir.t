use strict;
use warnings;
use FindBin ();
BEGIN { require "$FindBin::Bin/etc/legacy.pl" }
use Test::More tests => 6;
use Test::Mojo;
use Mojo::ByteStream qw/b/;
use File::Temp;
use Yars;
use Mojo::IOLoop::Server;
use Time::HiRes ();

$ENV{MOJO_MAX_MEMORY_SIZE} = 100;            # Force temp files.
$ENV{MOJO_TMPDIR}          = "/tmp/nosuchdir";
$ENV{CLUSTERICIOUS_CONF_DIR}      = dirname(__FILE__) . '/conf_071';
$ENV{CLUSTERICIOUS_TEST_CONF_DIR} = $ENV{CLUSTERICIOUS_CONF_DIR};
my $root = $ENV{YARS_TMP_ROOT} = File::Temp->newdir(CLEANUP => 1);
$ENV{LOG_LEVEL} = 'TRACE';
$ENV{YARS_PORT} = Mojo::IOLoop::Server->generate_port;
$ENV{YARS_TEST_PID_FILE} = File::Spec->catfile(File::Spec->tmpdir, "yars-test.$<.$$.0.pid");

my $tmp = File::Temp->newdir(CLEANUP => 1);
do {
  local $ENV{LOG_FILE} = "$tmp/yars.test.$<.log";
  my $yars_exe = yars_exe;
  system($^X, $yars_exe, 'start');

  my $retry = 100;
  my $sleep = 0.1;
  my $port = $ENV{"YARS_PORT"};
  note "waiting for port $port";
  while($retry--) {
    last if check_port($port);
    Time::HiRes::sleep($sleep);
  }
  die "not listening to port" unless $retry;

};

my $url = "http://localhost:$ENV{YARS_PORT}";

my $ua = Mojo::UserAgent->new();
is $ua->get($url.'/status')->res->json->{server_url}, $url, "started first server at $url";

my $content = 'x' x 1_000_000;
my $digest = b($content)->md5_sum->to_string;
my $filename = 'stuff.txt';

chomp (my $b64 = b($content)->md5_bytes->b64_encode);
my $tx = $ua->put("$url/file/$filename", {"Content-MD5" => $b64 }, $content);
ok $tx->success, "put to $url/file/$filename was a success";
my $location = $tx->res->headers->location;
ok $location, "got location header";
like $location, qr[.*$digest.*], "location had digest";

$ENV{MOJO_TMPDIR} = "/tmp";
my $got = $ua->get("$url/file/$filename/$digest");
my $res;
ok $res = $got->success, "got $url";
is length($res->body), length($content), "content lengths match";

done_testing();
