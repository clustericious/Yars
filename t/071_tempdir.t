#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Mojo;
use File::Basename qw/dirname/;
use Mojo::ByteStream qw/b/;
use File::Temp;
use Yars;

$ENV{MOJO_MAX_MEMORY_SIZE} = 100;            # Force temp files.
$ENV{MOJO_TMPDIR}          = "/tmp/nosuchdir";
$ENV{CLUSTERICIOUS_CONF_DIR}      = dirname(__FILE__) . '/conf_071';
$ENV{CLUSTERICIOUS_TEST_CONF_DIR} = $ENV{CLUSTERICIOUS_CONF_DIR};
$ENV{PERL5LIB}                    = join ':', @INC;
$ENV{PATH} = dirname(__FILE__) . "/../blib/script:$ENV{PATH}";
my $root = $ENV{YARS_TMP_ROOT} = File::Temp->newdir(CLEANUP => 1);
$ENV{LOG_LEVEL} = 'TRACE';

sub _sys {
    my $cmd = shift;
    system($cmd)==0 or die "Error running $cmd : $!";
}

_sys("LOG_FILE=/tmp/yars.test.$<.log yars start");

my $url = "http://localhost:9059";

sleep 3;
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

_sys("LOG_FILE=/tmp/yars.test.$<.log yars stop");

done_testing();
