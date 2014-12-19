#!/usr/bin/env perl

use lib '../lib';
use Yars::Client;
#use Smart::Comments;
use Mojo::ByteStream qw/b/;
use Parallel::ForkManager;

srand;

use strict;

my $how_many = $ARGV[0] || 10;
my $processes = 5;

warn "attempting $how_many puts\n";
#chomp (my $md5_b64 = b($content)->md5_bytes->b64_encode);


my $p = Parallel::ForkManager->new($processes);

my @locations;
for (1..$processes)  {
    $p->start and next;
    my $y = Yars::Client->new();
    srand(time.$$);
    for (1..$how_many) { ### putting...    [%] done
        my $r = rand 1;
        my $filename = "filename_$r";
        my $url = $y->_get_url("/file/$filename");
        $y->put("filename_$r", "content_$r" x 5000) or do  {
            warn "failed to put to $url :"
              . $y->errorstring . " "
              . $y->res->to_string;
              #. $y->client->tx->to_string;
            die "bailing out";
        };
        warn "file $_, pid $$" unless $_ % 500;
    }
    $p->finish;
}

$p->wait_all_children;

1;

