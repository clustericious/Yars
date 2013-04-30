use strict;
use warnings;
use File::HomeDir::Test;
use File::HomeDir;
use Test::More;
use Test::Mojo;
use Mojolicious;
use File::Spec;
use YAML ();

# this change to Mojolicious in version 3.85 broke the way we set the temp directory:
# https://github.com/kraih/mojo/commit/eff7e8dce836c75e21c1c1b3456fb3f8a9992ecb
# this test checks to see that Mojo::Asset::File#tmpdir is set before Mojo::Asset::File#handle is called
# if the internal ordering of these method calls is changed again in Mojolicious it might show
# up as an error here, but the important thing is that temp files are written to
# $disk_root/tmp and then moved the appropriate $disk_root/xx/xx/xx/... directory
# rather than $TMPDIR and then moved to $disk_root/xx/xx/xx/...

if(eval q{ use Monkey::Patch; use Yars::Client; *patch_class = \&Monkey::Patch::patch_class; 1 })
{ plan tests => 5 }
else
{ plan skip_all => 'test requires Monkey::Patch and Yars::Client' }

my $home = File::HomeDir->my_home;
mkdir(File::Spec->catdir($home, $_)) for qw( etc data tmp sample );
mkdir(File::Spec->catdir($home, 'data', "disk_$_")) for (0..9,'a'..'f');
YAML::DumpFile(File::Spec->catfile($home, 'etc', 'Yars.conf') => {
  url => 'http://localhost',
});
mkdir(File::Spec->catdir($home, qw( data disk_c tmp )));
do {
  my $fh;
  open($fh, '>', File::Spec->catfile($home, qw( data disk_c tmp right.txt )));
  close $fh;
};

my $t = Test::Mojo->new('Yars');
my $port = $t->ua->app_url->port;
$ENV{MOJO_TMPDIR} = File::Spec->catdir($home, 'tmp');
do { 
  my $fh;
  open($fh, '>', File::Spec->catfile($home, qw( tmp wrong.txt )));
  close $fh;
};

YAML::DumpFile(File::Spec->catfile($home, 'etc', 'Yars.conf'), {
  url => "http://localhost:$port",
  servers => [ {
    url => "http://localhost:$port",
    disks => [ 
      map {; 
        {
          root    => File::Spec->catdir($home, 'data', "disk_$_"),
          buckets => [ $_ ],
        }
      } (0..9,'a'..'f')
    ]
  } ],
});

my $sample_filename = File::Spec->catfile($home, 'sample', 'sample.yml');
YAML::DumpFile($sample_filename, {
  name => 'Optimus Prime',
  list => [ 1..512 ],
  hash => { map {; $_ => 1 } ( 'a'..'z','A'..'Z' ) },
});

my $client = do {
  my $c = Yars::Client->new;
  $c->client($t->ua);
  $c;
};
Yars::Tools->refresh_config;

$t->get_ok("http://localhost:$port/version")
  ->status_is(200);
like $t->tx->res->json->[0], qr{^(\d+\.\d+|dev)$}, "version = " . $t->tx->res->json->[0];

my $tmpdir;

do {
  my $patch1 = patch_class('Mojo::Asset::File', handle => sub {
    my($original, $self, @rest) = @_;
    $tmpdir = eval { $self->tmpdir; }; diag $@ if $@;
    $self->$original(@rest);
  });
  
  my $patch2 = patch_class('Mojo::Asset::File', tmpdir => sub {
    my($original, $self, $new_value) = @_;
    $self->$original($new_value);
  });
  
  $client->upload($sample_filename);
  
};

ok( -e File::Spec->catfile( $home, qw( data disk_c c6 51 3a 77 f5 47 ee c1 b8 b1 22 3b d1 0d a9 2f sample.yml )), 'file uploaded');
ok( -e File::Spec->catfile( $tmpdir, qw( right.txt )), 'used correct tmp directory');
