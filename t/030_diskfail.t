#!/usr/bin/env perl

use strict;
use warnings;

use File::Basename qw/dirname/;
use Test::More;
use Mojo::ByteStream qw/b/;
use File::Find::Rule;
use lib dirname(__FILE__);
use tlib qw/sys/;
use Yars;

my @urls = ("http://localhost:9051","http://localhost:9052");

$ENV{CLUSTERICIOUS_CONF_DIR} = dirname(__FILE__).'/conf3';
$ENV{CLUSTERICIOUS_TEST_CONF_DIR} = $ENV{CLUSTERICIOUS_CONF_DIR};
#$ENV{LOG_LEVEL} = "TRACE";
$ENV{MOJO_MAX_MEMORY_SIZE} = 10;
my $root = $ENV{YARS_TMP_ROOT} = File::Temp->newdir(CLEANUP => 1);

sub _slurp {
    my $file = shift;
    my @lines = IO::File->new("<$file")->getlines;
    return join '', @lines;
}

for my $which (qw/1 2/) {
    my $pid_file = "$root/yars.test.$<.${which}.hypnotoad.pid";
    if (-e $pid_file && kill 0, _slurp($pid_file)) {
        diag "killing running yars $which";
        sys("MOJO_MAX_MEMORY_SIZE=1 LOG_FILE=$root/yars.test.$<.$which.log YARS_WHICH=$which yars stop");
    }
    sys("MOJO_MAX_MEMORY_SIZE=1 LOG_FILE=$root/yars.test.$<.$which.log YARS_WHICH=$which yars start");
}

my $ua = Mojo::UserAgent->new();
$ua->max_redirects(3);
sleep 3;
is $ua->get($urls[0].'/status')->res->json->{server_url}, $urls[0], "started first server at $urls[0]";
is $ua->get($urls[1].'/status')->res->json->{server_url}, $urls[1], "started second server at $urls[1]";

my $i = 0;
my @contents = map { $_ x 5000 } <DATA>;
my @locations;
my @md5s;
my @filenames;
for my $content (@contents) {
    $i++;
    my $filename = "file_numero_$i";
    push @filenames, $filename;
    push @md5s, b($content)->md5_sum;
    my $tx = $ua->put("$urls[1]/file/$filename", { "Content-MD5" => $md5s[-1] }, $content);
    my $location = $tx->res->headers->location;
    ok $location, "Got location header";
    ok $tx->success, "put $filename to $urls[1]/file/$filename";
    push @locations, $location;
    if ($i==20) {
        # Make a disk unwriteable.
        File::Find::Rule->new->exec(sub {
             chmod 0555, $_ })->in("$root/three");
        #ok ( (chmod 0555, "$root/three"), "chmod 0555, $root/three");
    }
    if ($i==60) {
        # Make both disks on one host unwriteable.
        File::Find::Rule->new->exec(sub { chmod 0555, $_ })->in("$root/four");
        #ok ( (chmod 0555, "$root/four"), "chmod 0555, $root/four");
        #ok ( (chmod 0555, "$root/four/tmp"), "chmod 0555, $root/four/tmp");
    }
}

for my $url (@locations) {
    my $want = shift @contents;
    my $md5  = shift @md5s;
    my $filename = shift @filenames;
    ok $url, "We have a location for $filename";
    next unless $url;
    for my $attempt ($url, "$urls[0]/file/$md5/$filename", "$urls[1]/file/$md5/$filename") {
        my $tx = $ua->get($attempt);
        my $res;
        ok $res = $tx->success, "got $attempt";
        my $body = $res ? $res->body : '';
        is $body, $want, "content match for $filename at $attempt";
    }

}

sys("YARS_WHICH=1 yars stop");
sys("YARS_WHICH=2 yars stop");

done_testing();

__DATA__
head -100 /usr/share/dict/words
1080
10-point
10th
11-point
12-point
16-point
18-point
1st
2
20-point
2,4,5-t
2,4-d
2D
2nd
30-30
3-D
3-d
3D
3M
3rd
48-point
4-D
4GL
4H
4th
5-point
5-T
5th
6-point
6th
7-point
7th
8-point
8th
9-point
9th
-a
A
A.
a
a'
a-
a.
A-1
A1
a1
A4
A5
AA
aa
A.A.A.
AAA
aaa
AAAA
AAAAAA
AAAL
AAAS
Aaberg
Aachen
AAE
AAEE
AAF
AAG
aah
aahed
aahing
aahs
AAII
aal
Aalborg
Aalesund
aalii
aaliis
aals
Aalst
Aalto
AAM
aam
AAMSI
Aandahl
A-and-R
Aani
AAO
AAP
AAPSS
Aaqbiye
Aar
Aara
Aarau
AARC
aardvark
aardvarks
aardwolf
aardwolves
Aaren
Aargau
aargh
Aarhus
Aarika
Aaron
