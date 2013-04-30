use strict;
use warnings;
use autodie;
use v5.10;
use FindBin ();
BEGIN { require "$FindBin::Bin/etc/setup.pl" }
use File::HomeDir::Test;
use File::HomeDir;
use Test::More;
use Test::Mojo;
use Mojolicious;
use File::Spec;
use Scalar::Util qw( refaddr );
use YAML ();
use Yars;

$Yars::VERSION //= '0.77';

# this change to Mojolicious in version 3.85 broke the way we set the temp directory:
# https://github.com/kraih/mojo/commit/eff7e8dce836c75e21c1c1b3456fb3f8a9992ecb
# this test checks to see that Mojo::Asset::File#tmpdir is set before Mojo::Asset::File#handle is called
# if the internal ordering of these method calls is changed again in Mojolicious it might show
# up as an error here, but the important thing is that temp files are written to
# $disk_root/tmp and then moved the appropriate $disk_root/xx/xx/xx/... directory
# rather than $TMPDIR and then moved to $disk_root/xx/xx/xx/...

if(eval q{ use Monkey::Patch; use Yars::Client; *patch_class = \&Monkey::Patch::patch_class; 1 })
{ plan tests => 6 }
else
{ plan skip_all => 'test requires Monkey::Patch and Yars::Client' }

my $home = File::HomeDir->my_home;
mkdir(File::Spec->catdir($home, $_)) for qw( etc data tmp sample );
mkdir(File::Spec->catdir($home, 'data', "disk_$_")) for (0..9,'a'..'f');
YAML::DumpFile(File::Spec->catfile($home, 'etc', 'Yars.conf') => {
  url => 'http://localhost',
});
mkdir(File::Spec->catdir($home, qw( data disk_5 tmp )));
do {
  my $fh;
  open($fh, '>', File::Spec->catfile($home, qw( data disk_5 tmp right.txt )));
  close $fh;
};

my $t = Test::Mojo->new('Yars');
my $port = $t->ua->app_url->port;
$ENV{MOJO_TMPDIR} = File::Spec->catdir($home, 'tmp');
$ENV{MOJO_MAX_MEMORY_SIZE} = 5;            # Force temp files.
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

my $sample_filename = File::Spec->catfile($home, 'sample', 'sample.txt');
do {
  my $fh;
  open($fh, '>', $sample_filename);
  binmode $fh;
  print $fh 'hello world';
  close $fh;
};

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
my $path;

do {

  my $refaddr;

  $t->app->hook(after_build_tx => sub {
    my ( $tx, $app ) = @_;
    $tx->req->content->on(body => sub {
      my $content = shift;
      $content->asset->on(upgrade => sub {
          my ( $mem, $file ) = @_;
          $refaddr = refaddr $file if $tx->req->url =~ m{/file/sample.txt/};
      });
    })
  });

  my $patch1 = patch_class('Mojo::Asset::File', handle => sub {
    my($original, $self, @rest) = @_;
    if(defined $refaddr && refaddr($self) == $refaddr)
    {
      if(defined $tmpdir)
      {
        die unless $tmpdir eq $self->tmpdir;
      }
      else
      {
        $tmpdir = eval { $self->tmpdir; }; diag $@ if $@;
      }
    }
    my @ret;
    my $ret;
    if(wantarray) {
      @ret = $self->$original(@rest);
    } else {
      $ret = $self->$original(@rest);
    }
    if(defined $refaddr && refaddr($self) == $refaddr)
    {
      if(defined $path)
      {
        die unless $self->path eq $path;
      }
      else
      {
        $path = $self->path;
      }
    }
    wantarray ? return(@ret) : return($ret);
  });

  $client->upload($sample_filename);
  
};

ok( -e File::Spec->catfile( $home, qw( data disk_5 5e b6 3b bb e0 1e ee d0 93 cb 22 bb 8f 5a cd c3 sample.txt )), 'file uploaded');
ok( -e File::Spec->catfile( $tmpdir, qw( right.txt )), 'used correct tmp directory ' . ($tmpdir//'undef'));
like $path, qr{disk_5}, 'path = ' . $path;

