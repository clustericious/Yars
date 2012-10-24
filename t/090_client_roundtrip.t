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
my $name = "$new";

ok -e $name, "wrote $name";

ok $y->upload($name), "uploading $name";
is $y->res->code, '201', 'Created';

my $md5 = digest_file_hex($name,'MD5');
my $content = $y->get($md5,basename($name));
ok $content, "got content";
is $content, $data, "got same content";

done_testing ();
