use strict;
use warnings;
use FindBin ();
BEGIN { require "$FindBin::Bin/etc/legacy.pl" }
use File::HomeDir::Test;
use Test::More tests => 911;
use Mojo::ByteStream qw/b/;
use File::Find::Rule;
use Yars;
use Mojo::Loader;
use Mojo::JSON;

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
my @contents = do {
  my $loader = Mojo::Loader->new;
  $loader->load('main');
  map { $_ x 5000 } @{ Mojo::JSON->new->decode($loader->data('main', 'test_data.json')) };
};
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

@@ test_data.json
["head -100 /usr/share/dict/words\n","1080\n","10-point\n","10th\n","11-point\n","12-point\n","16-point\n","18-point\n","1st\n","2\n","20-point\n","2,4,5-t\n","2,4-d\n","2D\n","2nd\n","30-30\n","3-D\n","3-d\n","3D\n","3M\n","3rd\n","48-point\n","4-D\n","4GL\n","4H\n","4th\n","5-point\n","5-T\n","5th\n","6-point\n","6th\n","7-point\n","7th\n","8-point\n","8th\n","9-point\n","9th\n","-a\n","A\n","A.\n","a\n","a'\n","a-\n","a.\n","A-1\n","A1\n","a1\n","A4\n","A5\n","AA\n","aa\n","A.A.A.\n","AAA\n","aaa\n","AAAA\n","AAAAAA\n","AAAL\n","AAAS\n","Aaberg\n","Aachen\n","AAE\n","AAEE\n","AAF\n","AAG\n","aah\n","aahed\n","aahing\n","aahs\n","AAII\n","aal\n","Aalborg\n","Aalesund\n","aalii\n","aaliis\n","aals\n","Aalst\n","Aalto\n","AAM\n","aam\n","AAMSI\n","Aandahl\n","A-and-R\n","Aani\n","AAO\n","AAP\n","AAPSS\n","Aaqbiye\n","Aar\n","Aara\n","Aarau\n","AARC\n","aardvark\n","aardvarks\n","aardwolf\n","aardwolves\n","Aaren\n","Aargau\n","aargh\n","Aarhus\n","Aarika\n","Aaron\n"]

