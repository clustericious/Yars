use strict;
use warnings;
use Test::More;
use File::Spec ();
use Mojo::IOLoop::Server ();
use File::Basename qw( dirname );

$ENV{HARNESS_ACTIVE} = 1;
delete $ENV{CLUSTERICIOUS_CONF_DIR};

sub two_urls
{
  my $up = File::Spec->updir;

  $ENV{CLUSTERICIOUS_CONF_DIR} = File::Spec->catdir(dirname(__FILE__), $up, shift());
  $ENV{CLUSTERICIOUS_TEST_CONF_DIR} = $ENV{CLUSTERICIOUS_CONF_DIR};
  note "config = $ENV{CLUSTERICIOUS_CONF_DIR}";

  $ENV{YARS_PORT1} = Mojo::IOLoop::Server->generate_port;
  $ENV{YARS_PORT2} = Mojo::IOLoop::Server->generate_port;
  my $root = $ENV{YARS_TMP_ROOT} = File::Temp->newdir(CLEANUP => 1);

  my @urls = ("http://localhost:$ENV{YARS_PORT1}","http://localhost:$ENV{YARS_PORT2}");
  note "url1 $urls[0]";
  note "url2 $urls[1]";

  my $yars_exe = File::Spec->catfile(dirname(__FILE__), $up, $up, 'blib', 'script', 'yars');
  unless(-e $yars_exe)
  {
    use autodie;
    mkdir(File::Spec->catdir($root,'bin'));
    my $in;
    my $out;
    $yars_exe = File::Spec->catfile($root, 'bin', 'yars.pl');
    open($in,  '<', File::Spec->catfile(dirname(__FILE__), $up, $up, 'bin', 'yars'));
    open($out, '>', $yars_exe);
    my $shebang = <$in>;
    print $out "#!$^X\n";
    while(<$in>) { print $out $_ }
    close $in;
    close $out;
    chmod 0700, $yars_exe;
  }

  for my $which (qw/1 2/) {
    local $ENV{LOG_FILE}   = File::Spec->catfile(File::Spec->tmpdir, "yars-test.$<.$which.log");
    note "log = $ENV{LOG_FILE}";
    local $ENV{YARS_WHICH} = $which;
    note "% $^X $yars_exe start";
    system($^X, $yars_exe, 'start');
  }

  ($root, @urls);
}

1;
