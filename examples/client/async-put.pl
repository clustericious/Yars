#!/usr/bin/env perl

use Yars::Client;
use Mojo::ByteStream qw/b/;

use strict;

my $how_many = $ARGV[0] || 10;

warn "attempting $how_many puts\n";

sub _hex2b64 {
    my $hex = shift or return;
    my $b64 = b(pack 'H*', $hex)->b64_encode;
    local $/="\n";
    chomp $b64;
    return $b64;
}

my $y = Yars::Client->new();
my $ua = Mojo::UserAgent->new();

my $on_file = 1;

sub _newfile {
    my $r = rand 1;
    my $filename = "filename_$r";
    $filename =~ tr/0-9a-zA-Z//dc;
    my $content = "content_$r" x 5000;
    my $md5 = b($content)->md5_sum;
    my $md5_b64 = _hex2b64($md5);
    my $server = $y->_server_for($md5) or die "no server for $md5";
    my $url = Mojo::URL->new($server);
    $url->path("/file/$filename");
    return ( "$url", { Connection => "Close", "Content-MD5" => $md5_b64 }, $content );
}

my $on_finish;
$on_finish = sub {
    my ( $ua, $tx ) = @_;
    my $res = $tx->success or do {
        warn "failed to put :" . $tx->error;
        warn "bailing out";
        Mojo::IOLoop->stop;
    };
    if ( $on_file++ >= $how_many ) {
        warn "done";
        Mojo::IOLoop->stop;
    }
    my ($url,$h,$c) = _newfile();
    warn  "now doing file $on_file : $url" unless $on_file % 100;
    $ua->put($url, $h, $c, $on_finish);
};

for (1..20) {
    $ua->put( _newfile(),  $on_finish );
}

Mojo::IOLoop->start;

1;

