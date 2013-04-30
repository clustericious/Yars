#!perl

use Test::More;
use Test::Mojo;
use Sys::Hostname qw/hostname/;
use File::Temp;
use File::Basename qw/basename/;
use Digest::file qw/digest_file_hex/;
use strict;

BEGIN {
    my $min = '0.80';
    eval "use Yars::Client $min";
    if ($@) {
        plan skip_all => "Yars::Client $min required";
    }
};
use Yars;

diag "Testing Yars::Client $Yars::Client::VERSION";

my $root = File::Temp->newdir(CLEANUP => 1);
my $t = Test::Mojo->new("Yars");
$t->app->config->servers(
    default => [{ disks => [ { root => $root, buckets => [ '0' .. '9', 'A' .. 'F' ] } ] }]
);
my $url = $t->ua->app_url;
$t->app->config->{url} = $url;
$t->app->config->servers->[0]{url} = $url;
Yars::Tools->refresh_config($t->app->config);

my $y = Yars::Client->new(app => 'Yars');
$y->client($t->ua);
my $st = $y->status;
is_deeply $st, {
    app_name        => "Yars",
    server_hostname => hostname,
    server_url      => undef,
    server_version  => $Yars::VERSION
  }, "got the right status";

my $data = "some data $$ ".time;
my $new = File::Temp->new;
print $new $data;
$new->close;
my $path = "$new";
my $filename = basename($path);

ok -e $path, "wrote $path";

ok $y->upload($path), "uploading $filename";
is $y->res->code, '201', 'Created';

my $md5 = digest_file_hex($path,'MD5');
my $content = $y->get($md5,$filename);
ok $content, "got content";
is $content, $data, "got same content";

my $download_dir = File::Temp->newdir(CLEANUP => 1);
chdir $download_dir or die $!;
ok $y->download($md5,$filename), "Downloaded $filename";
ok -e $filename, "Downloaded $filename";
my $got = join "", IO::File->new("<$filename")->getlines;
is $got, $data, "got same contents";
chdir "$download_dir/..";

# TODO
# my $status = $y->check_manifest($filename);
# diag explain $status;

done_testing ();

