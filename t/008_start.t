use strict;
use warnings;
use autodie;
use File::HomeDir::Test;
use File::HomeDir;
use File::Spec;
use Test::More tests => 6;
use Mojo::IOLoop::Server ();
use YAML qw( DumpFile );
use Yars;

my $port = Mojo::IOLoop::Server->generate_port;

like $port, qr{^\d+$}, "port = $port";

my $home = File::HomeDir->my_home;
ok -d $home, "home = $home";

my $etc_dir = File::Spec->catdir($home, 'etc');
mkdir $etc_dir;
ok -d $etc_dir, "etc_dir = $etc_dir";

my $data_dir = File::Spec->catdir($home, 'data');
mkdir $data_dir;
ok -d $data_dir, "data_dir = $data_dir";

my $conf_file = File::Spec->catfile($etc_dir, 'Yars.conf');
DumpFile($conf_file, {
  url => "http://localhost:$port",
  servers => [ {
    url   => "http://localhost:$port",
    disks => [ {
      root    => File::Spec->catdir($data_dir),
      buckets => [ 0..9, 'a'..'f' ],
    } ],
  } ],
});
ok -f $conf_file, "conf_file = $conf_file";
note do {
  open my $fh, '<', $conf_file;
  local $/;
  my $data = <$fh>;
  close $fh;
  $data;
};

$ENV{MOJO_APP} = 'Yars';
my $app = eval { Yars->new };
diag $@ if $@;
isa_ok $app, 'Yars';
