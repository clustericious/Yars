use strict;
use warnings;
use FindBin ();
BEGIN { require "$FindBin::Bin/etc/legacy.pl" }
use File::HomeDir::Test;
use Test::More tests => 97;
use Mojo::ByteStream qw/b/;
use Yars;
use Clustericious::Config;

my($root, @urls) = two_urls('conf2');

sub _normalize {
    my ($one) = @_;
    return [ sort { $a->{md5} cmp $b->{md5} } @$one ];
}

my $ua = Mojo::UserAgent->new();
$ua->max_redirects(3);
eval {
  is $ua->get($urls[0].'/status')->res->json->{server_url}, $urls[0], "started first server at $urls[0]";
  is $ua->get($urls[1].'/status')->res->json->{server_url}, $urls[1], "started second server at $urls[1]";
};

my $status = $ua->get($urls[0].'/servers/status')->res->json;
is_deeply($status, {
        "http://localhost:$ENV{YARS_PORT1}" => { "$root/one" => "up" },
        "http://localhost:$ENV{YARS_PORT2}" => { "$root/two" => "up" },
    }
);

my $i = 0;
my @contents = <DATA>;
my @locations;
my @digests;
my @filenames;
my @sizes;
for my $content (@contents) {
    $i++;
    my $filename = "file_numero_$i";
    push @filenames, $filename;
    push @digests, b($content)->md5_sum;
    push @sizes, b($content)->size;
    my $tx = $ua->put("$urls[1]/file/$filename", {}, $content);
    my $location = $tx->res->headers->location;
    ok $location, "Got location header";
    ok $tx->success, "put $filename to $urls[1]/file/filename";
    push @locations, $location;
}

my $manifest;
my @filelist;
$i = 0;
for my $url (@locations) {
    my $content  = $contents[$i];
    my $filename = $filenames[$i];
    my $size     = $sizes[$i];
    my $md5      = $digests[ $i++ ];
    $manifest .= "$md5  $filename\n";
    push @filelist, { filename => $filename, md5 => "$md5" };
    next unless $url; # error will occur above
    {
        my $tx = $ua->get($url);
        my $res;
        ok $res = $tx->success, "got $url";
        is $res->body, $content, "content match";
    }
    {
        my $tx = $ua->head("$urls[0]/file/$md5/$filename");
        ok $tx->success, "head $urls[0]/file/$md5/$filename";
        is $tx->res->headers->content_length, $size;
    }
}

$manifest .= "11f488c161221e8a0d689202bc8ce5cd  dummy\n";

my $tx = $ua->post( "$urls[0]/check/manifest?show_found=1", { "Content-Type" => "application/json" },
    Mojo::JSON->new->encode( { manifest => $manifest } ) );
my $res = $tx->success;
ok $res, "posted to manifest";
is $res->code, 200, "got 200 for manifest";
ok eq_set( $res->json->{missing},
    [ { filename => "dummy", md5 => "11f488c161221e8a0d689202bc8ce5cd" } ] ),
  "none missing";
is_deeply (_normalize($res->json->{found}),_normalize(\@filelist),'found all');

for my $url (@locations) {
    my $content  = shift @contents;
    my $filename = shift @filenames;
    my $md5      = shift @digests;
    {
        my $tx = $ua->delete("$urls[0]/file/$md5/$filename");
        ok $tx->success, "delete $urls[0]/file/$md5/$filename";
        diag join ',',$tx->error if $tx->error;
    }
    {
        my $tx = $ua->get("$urls[0]/file/$md5/$filename");
        is $tx->res->code, 404, "Not found after deleting";
        $tx = $ua->get("$urls[1]/file/$md5/$filename");
        is $tx->res->code, 404, "Not found after deleting";
    }
}

stop_a_yars($_) for 1..2;

__DATA__
this is one file
this is another file
this is a third file
these files are all different
no two are the same
and some of them have md5s that make them go to
the first server, while others go to the
second server.
Every file is one line long.
buh bye
