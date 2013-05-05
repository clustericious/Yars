use strict;
use warnings;
use FindBin ();
BEGIN { require "$FindBin::Bin/etc/legacy.pl" }
use File::HomeDir::Test;
use Test::More tests => 911;
use Mojo::ByteStream qw/b/;
use File::Find::Rule;
use Yars;

$ENV{MOJO_MAX_MEMORY_SIZE} = 10;
$ENV{YARS_TEST_EXPIRATION} = 120;
my($root, @urls) = do {
  local $ENV{MOJO_MAX_MEMORY_SIZE} = 1;
  two_urls('conf3');
};

my $ua = Mojo::UserAgent->new();
$ua->max_redirects(3);
eval {
  is $ua->get($urls[0].'/status')->res->json->{server_url}, $urls[0], "started first server at $urls[0]";
  is $ua->get($urls[1].'/status')->res->json->{server_url}, $urls[1], "started second server at $urls[1]";
};
if(my $error = $@)
{
  diag "FAILED: with $error";
  foreach my $which (1..2)
  {
    use autodie;
    diag "LOG $which";
    open my $fh, '<', "$root/yars.test.$<.$which.log";
    diag <$fh>;
    close $fh;
  }
  exit;
}

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

stop_a_yars($_) for 1..2;

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
