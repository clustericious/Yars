#!/usr/bin/env perl

use strict;
use warnings;

use Mojo::ByteStream qw/b/;
use File::Basename qw/dirname/;
use Test::More;
use Yars;

my @urls = ("http://localhost:9051","http://localhost:9052");

$ENV{CLUSTERICIOUS_CONF_DIR} = dirname(__FILE__).'/conf3';
$ENV{CLUSTERICIOUS_TEST_CONF_DIR} = $ENV{CLUSTERICIOUS_CONF_DIR};
$ENV{PERL5LIB} = join ':', @INC;
$ENV{PATH} = dirname(__FILE__)."/../blib/script:$ENV{PATH}";
$ENV{LOG_LEVEL} = "WARN";
my $root = $ENV{YARS_TMP_ROOT} = File::Temp->newdir(CLEANUP => 1);

sub _sys {
    my $cmd = shift;
    system($cmd)==0 or die "Error running $cmd : $!";
}

sub _slurp {
    my $file = shift;
    my @lines = IO::File->new("<$file")->getlines;
    return join '', @lines;
}

for my $which (qw/1 2/) {
    my $pid_file = "/tmp/yars.test.${which}.hypnotoad.pid";
    if (-e $pid_file && kill 0, _slurp($pid_file)) {
        diag "killing running yars $which";
        _sys("LOG_FILE=/tmp/yars.test.$<.log YARS_WHICH=$which yars stop");
    }
    _sys("LOG_FILE=/tmp/yars.test.$<.log YARS_WHICH=$which yars start");
}

my $ua = Mojo::UserAgent->new();
sleep 10;
is $ua->get($urls[0].'/status')->res->json->{server_url}, $urls[0], "started first server at $urls[0]";
is $ua->get($urls[1].'/status')->res->json->{server_url}, $urls[1], "started second server at $urls[1]";

my $i = 0;
my @contents = <DATA>;
my @locations;
my %assigned; # server => { disk => count }
for my $content (@contents) {
    for (b($content)->md5_sum) {
        /^[0-3]/i  and $assigned{"http://localhost:9051"}{"$root/one"}{count}++;
        /^[4-7]/i  and $assigned{"http://localhost:9051"}{"$root/two"}{count}++;
        /^[89AB]/i and $assigned{"http://localhost:9052"}{"$root/three"}{count}++;
        /^[CDEF]/i and $assigned{"http://localhost:9052"}{"$root/four"}{count}++;
    }
    $i++;
    my $filename = "file_numero_$i";
    my $tx = $ua->put("$urls[0]/file/$filename", {}, $content);
    my $location = $tx->res->headers->location;
    ok $location, "Got location header";
    ok $tx->success, "put $filename to $urls[0]/file/$filename";
    push @locations, $location;
    if ($i==20) {
        # Make a host unreachable
        _sys("YARS_WHICH=2 yars stop");
    }
}

$i = 0;
for my $url (@locations) {
    my $want = shift @contents;
    next unless $url;
    next if $i++ < 20; # skip ones that went to host that died
    my $tx = $ua->get($url);
    my $res;
    ok $res = $tx->success, "got $url";
    my $body = $res ? $res->body : '';
    is $body, $want, "content match for file $i at $url";
}

# Now start it back up.
_sys("YARS_WHICH=2 yars start");

TODO: {
    local $TODO = "Run yars_fast_balance";
    for my $host (keys %assigned) {
        my $tx = $ua->get("$host/disk/usage?count=1");
        my $res;
        ok $res = $tx->success, "got usage";
        unless ($res) {
            diag "failed to get $host/disk/usage?count=1".$tx->error;
            next;
        }
        #my $got = $res->json;
        #for my $disk (keys %$got) {
        #    is( $got->{$disk}{count}, $assigned{$host}{$disk}{count}, "$host,$disk has the right count ($assigned{$host}{$disk}{count})" );
        #}
    }
}

_sys("YARS_WHICH=1 yars stop");
_sys("YARS_WHICH=2 yars stop");

done_testing();

__DATA__
tail -100 /usr/share/dict/words
Zygosaccharomyces
zygose
zygoses
zygosis
zygosities
zygosity
zygosperm
zygosphenal
zygosphene
zygosphere
zygosporange
zygosporangium
zygospore
zygosporic
zygosporophore
zygostyle
zygotactic
zygotaxis
zygote
zygotene
zygotenes
zygotes
zygotic
zygotically
zygotoblast
zygotoid
zygotomere
-zygous
zygous
zygozoospore
zym-
zymase
zymases
-zyme
zyme
zymes
zymic
zymin
zymite
zymo-
zymochemistry
zymogen
zymogene
zymogenes
zymogenesis
zymogenic
zymogenous
zymogens
zymogram
zymograms
zymoid
zymologic
zymological
zymologies
zymologist
zymology
zymolyis
zymolysis
zymolytic
zymome
zymometer
zymomin
zymophore
zymophoric
zymophosphate
zymophyte
zymoplastic
zymosan
zymosans
zymoscope
zymoses
zymosimeter
zymosis
zymosterol
zymosthenic
zymotechnic
zymotechnical
zymotechnics
zymotechny
zymotic
zymotically
zymotize
zymotoxic
zymurgies
zymurgy
Zyrenian
Zyrian
Zyryan
Zysk
zythem
Zythia
zythum
Zyzomys
Zyzzogeton
zyzzyva
zyzzyvas
ZZ
Zz
zZt
ZZZ
