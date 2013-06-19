use strict;
use warnings;
use v5.10;
use Test::More;
use File::Spec ();
use Mojo::IOLoop::Server ();
use File::Basename qw( dirname );
use Time::HiRes ();
use File::Temp qw( tempdir );

$ENV{HARNESS_ACTIVE} = 1;
delete $ENV{CLUSTERICIOUS_CONF_DIR};

sub yars_exe
{
  state $yars_exe;
  my $up = File::Spec->updir;
  my $root = tempdir( CLEANUP => 1 );
  
  unless(defined $yars_exe)
  {
    $yars_exe = File::Spec->catfile(dirname(__FILE__), $up, $up, 'blib', 'script', 'yars');
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
  }
  
  $yars_exe;
}

sub two_urls
{
  my $up = File::Spec->updir;

  $ENV{CLUSTERICIOUS_CONF_DIR} = File::Spec->catdir(dirname(__FILE__), $up, shift());
  $ENV{CLUSTERICIOUS_TEST_CONF_DIR} = $ENV{CLUSTERICIOUS_CONF_DIR};
  note "config = $ENV{CLUSTERICIOUS_CONF_DIR}";

  $ENV{YARS_PORT1} = Mojo::IOLoop::Server->generate_port;
  $ENV{YARS_PORT2} = Mojo::IOLoop::Server->generate_port;
  my $root = $ENV{YARS_TMP_ROOT} = File::Temp->newdir(CLEANUP => 1);

  my @urls = ("http://127.0.0.1:$ENV{YARS_PORT1}","http://127.0.0.1:$ENV{YARS_PORT2}");
  note "url1 $urls[0]";
  note "url2 $urls[1]";

  start_a_yars($_) for 1..2;

  ($root, @urls);
}

sub stop_a_yars
{
  my $which = shift;
  local $ENV{LOG_FILE}           = File::Spec->catfile(File::Spec->tmpdir, "yars-test.$<.$which.log");
  local $ENV{YARS_TEST_PID_FILE} = File::Spec->catfile(File::Spec->tmpdir, "yars-test.$<.$$.$which.pid");
  local $ENV{YARS_WHICH}         = $which;
  note "stop $which";
  my $yars_exe = yars_exe();
  system($^X, $yars_exe, 'stop');
  note "stopped";

  my $retry = 100;
  my $sleep = 0.1;
  my $port = $ENV{"YARS_PORT$ENV{YARS_WHICH}"};
  note "waiting for port $port";
  while($retry--) {
    return unless check_port($port);
    Time::HiRes::sleep($sleep);
  }
  die "not listening to port";

}

sub dump_log_files
{
  my $dir;
  opendir($dir, File::Spec->tmpdir);
  my @list = grep /^yars-test.*\.log$/, readdir $dir;
  closedir $dir; 
  foreach my $fn (map { File::Spec->catfile(File::Spec->tmpdir, $_) } @list)
  {
    diag "== $fn ==";
    open my $fh, '<', $fn;
    local $/;
    diag <$fh>;
    close $fh;
  }
}

sub start_a_yars
{
  my $which = shift;
  local $ENV{LOG_FILE}   = File::Spec->catfile(File::Spec->tmpdir, "yars-test.$<.$which.log");
  local $ENV{YARS_TEST_PID_FILE} = File::Spec->catfile(File::Spec->tmpdir, "yars-test.$<.$$.$which.pid");
  local $ENV{YARS_WHICH} = $which;
  note "start $which";
  my $yars_exe = yars_exe();
  
  system($^X, $yars_exe, 'start');
  if($?)
  {
    diag "yars start FAILED ($^X, $yars_exe, 'start')";
    if($? == -1)
    {
      diag "failed to execute: $!\n";
    }
    elsif($? & 127) 
    {
      diag "died with siganl " . ($? & 127);
    }
    else
    {
      diag "child exited with " . ($?>>8);
    }
    dump_log_files();
    die "test won't work without yars";
  }
  
  note "started";
  
  my $retry = 100;
  my $sleep = 0.1;
  my $port = $ENV{"YARS_PORT$ENV{YARS_WHICH}"};
  note "waiting for port $port";
  while($retry--) {
    return if check_port($port);
    Time::HiRes::sleep($sleep);
  }
  dump_log_files();
  die "not listening to port";
}

sub check_port
{
  my $port = shift;
  require IO::Socket::INET;
  my $sock = IO::Socket::INET->new(
    Proto    => 'tcp',
    PeerAddr => '127.0.0.1',
    PeerPort => $port,
  );
  if($sock)
  {
    close $sock;
    return 1;
  }
  else
  {
    return 0;
  }
}

1;
