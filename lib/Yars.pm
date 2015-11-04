package Yars;

use strict;
use warnings;
use 5.010.1;
use Mojo::Base 'Clustericious::App';
use Yars::Routes;
use Yars::Tools;
use Mojo::ByteStream qw/b/;
use File::Path qw/mkpath/;
use Log::Log4perl qw(:easy);
use Number::Bytes::Human qw( format_bytes parse_bytes );

# ABSTRACT: Yet Another RESTful-Archive Service
# VERSION

=head1 DESCRIPTION

Yars is a simple RESTful server for data storage.

It allows files to be PUT and GET based on their md5 sums
and filenames, and uses a distributed hash table to store
the files across any number of hosts and disks.

Files are assigned to disks and hosts based on their md5s
in the following manner :

The first N digits of the md5 are considered the "bucket" for
a file.  e.g. for N=2, 256 buckets are then distributed among
the disks in proportion to the size of each disk.  The bucket
distribution is done manually as part of the configuration (with
the aid of an included tool, L<yars_generate_diskmap>).

The server is controlled with the command line tool L<yars>.

The basic operations of a running yars cluster are supporting
requests of the form

  PUT http://$host/file/$filename
  GET http://$host/file/$md5/$filename
  HEAD http://$host/file/$md5/$filename
  GET http://$host/bucket_map

to store and retrieve files, where $host may be any of the
hosts in the cluster, $md5 is the md5 of the content, and
$filename is a filename for the content to be stored.  See
L<Yars::Routes> for documentation of other routes.

Failover is handled in the following manner :

If the host to which a file is assigned is not available, then
the file will be "stashed" on the filesystem for the host
to which it was sent.  If there is no space there, other
hosts and disks will be tried until an available one is
found.  Because of this failover mechanism, the "stash"
must be checked whenever a GET request is handled.
A successful GET will return quickly, but an
unsuccessful one will take longer because all of the stashes
on all of the servers must be checked before a "404 Not Found"
is returned.

Another tool L<yars_fast_balance> is provided which takes
files from stashes and returns them to their correct
locations.

A client L<Yars::Client> is also available (in a separate
distribution), for interacting with a yars server.

=head1 EXAMPLES

=head2 simple single server configuration

This creates a single Yars server using hypnotoad with sixteen buckets.

Create a configuration file in C<~/etc/Yars.conf> with this
content:

 ---
 start_mode : 'hypnotoad'
 url : http://localhost:9999
 hypnotoad :
   pid_file : <%= file home, 'var/run/yars.pid' %>
   listen :
      - http://localhost:9999
 servers :
 - url : http://localhost:9999
   disks :
     - root : <%= file home, 'var/data/disk1' %>
       buckets : <%= json [ 0..9, 'a'..'f' ] %>
 
Create the directories needed for the server:

 % mkdir -p ~/var/run ~/var/data

Now you can start the server process

 % yars start

Now verify that it works:

 % curl http://localhost:9999/status
 {"server_url":"http://localhost:9999","server_version":"1.11","app_name":"Yars","server_hostname":"iscah"}

You can also verify that it works with L<yarsclient>:

 % yarsclient status
 ---
 app_name: Yars
 server_hostname: iscah
 server_url: http://localhost:9999
 server_version: '1.11'

Or via L<Yars::Client>:

 % perl -MYars::Client -MYAML::XS=Dump -E 'say Dump(Yars::Client->new->status)'
 ---
 app_name: Yars
 server_hostname: iscah
 server_url: http://localhost:9999
 server_version: '1.11'

Now try storing a file:

 % echo "hi" | curl -D headers.txt -T - http://localhost:9999/file/test_file1
 ok
 % grep Location headers.txt 
 Location: http://localhost:9999/file/764efa883dda1e11db47671c4a3bbd9e/test_file1

You can use the Location header to fetch the file at a later time

 % curl http://localhost:9999/file/764efa883dda1e11db47671c4a3bbd9e/test_file1
 hi

With L<yarsclient>

 % echo "hi" > test_file2
 % md5sum test_file2
 764efa883dda1e11db47671c4a3bbd9e  test_file2
 % yarsclient upload test_file2
 
 ... some time later ...
 
 % yarsclient downbload test_file2 764efa883dda1e11db47671c4a3bbd9e

You can see the HTTP requests and responses using the C<--trace> option:

 % yarsclient --trace upload test_file2
 % yarsclient --trace download test_file2 764efa883dda1e11db47671c4a3bbd9e

And from Perl:

 use 5.010;
 use Yars::Client;
 use Digest::MD5 qw( md5_hex );
 
 my $y = Yars::Client->new;
 
 # filename as first argument,
 # reference to content as second argument
 $y->upload("test_file3", \"hi\n");
 
 # you can also skip the content like this:
 # $y->upload("test_file3");
 # to upload content from a local file
 
 my $md5 = md5_hex("hi\n");
 
 $y->download("test_file3", $md5);

=head2 Multiple hosts

To install Yars on a cluster of several hosts, the configuration
for each host should be identical, except that the 'url'
should reflect the host on which the server is running.

To accomplish this, the above configuration may be divided
into two files, one with the bucket map, and another with
the server specific information.

    yars1 ~$ cat > ~/etc/Yars.conf :
    ----
    extends_config 'disk_map';
    url : http://yars1:9999
    hypnotoad :
      pid_file : /tmp/yars.pid
      listen :
         - http://yars1:9999

    yars2 ~$ cat > ~/etc/Yars.conf :
    ----
    extends_config 'disk_map';
    url : http://yars2:9999
    hypnotoad :
      pid_file : /tmp/yars.pid
      listen :
         - http://yars2:9999

    Then on both servers :
    $ cat > ~/etc/disk_map.conf :
    servers :
    - url : http://yars1:9999
      disks :
        - root : /usr/local/data/disk1
          buckets : [ <%= join ',', '0'..'9' %> ]
    - url : http://yars2:9999
      disks :
        - root : /usr/local/data/disk1
          buckets : [ <%= join ',', 'a'..'f' %> ]

Then run "yars start" on both servers and voila, you
have an archive.

See also, L<clad>, for a tool to facilitate
running "yars start" on multiple hosts at once.

L<Yars> is the application package, it inherits from
L<Clustericious::App> and overrides the following
methods :

=head2 Accelerated downloads with nginx

TODO

=cut

has secret => rand;

sub startup {
    my $self = shift;

    $self->hook(before_dispatch => sub {
        my($c) = @_;
        my $stream = Mojo::IOLoop->stream($c->tx->connection);
        return unless defined $stream;
        $stream->timeout(3000);
    });

    my $max_size = 53687091200;

    my $tools;

    $self->hook(
        after_build_tx => sub {
            # my($tx,$app) = @_;
            my ( $tx ) = @_;
            $tx->req->max_message_size($max_size);
            $tx->req->content->on(body => sub {
                    my $content = shift;
                    my $md5_b64 = $content->headers->header('Content-MD5') or return;
                    my $md5 = unpack 'H*', b($md5_b64)->b64_decode;
                    my $disk = $tools->disk_for($md5) or return;
                    my $tmpdir = join '/', $disk, 'tmp';
                    -d $tmpdir or do { mkpath $tmpdir;  chmod 0777, $tmpdir; };
                    -w $tmpdir or chmod 0777, $tmpdir;
                    $content->asset->on(
                        upgrade => sub {
                            #my ( $mem, $file ) = @_;
                            $_[1]->tmpdir($tmpdir);
                        }
                    );
                }
            );
        }
    );
    
    $self->SUPER::startup(@_);
    
    $tools = Yars::Tools->new($self->config);

    $self->hook(
        before_dispatch => sub {
            $tools->refresh_config($self->config);
        }
    );

    $self->helper( tools => sub { $tools } );

    if(my $time = $self->config->{test_expiration}) {
        require Clustericious::Command::stop;
        WARN "this process will stop after $time seconds";
        Mojo::IOLoop->timer($time => sub { 
            WARN "self terminating after $time seconds";
            eval { Clustericious::Command::stop->run };
            WARN "error in stop: $@" if $@;
        });
    }
    
    $max_size = parse_bytes($self->config->max_message_size_server(default => 53687091200));
    INFO "max message size = " . format_bytes($max_size) . " ($max_size)";
}

sub sanity_check
{
    my($self) = @_;

    return 0 unless $self->SUPER::sanity_check;

    my $sane = 1;
    
    my($url) = grep { $_ eq $self->config->url } map { $_->{url} } @{ $self->config->{servers} };
    
    unless(defined $url)
    {
        say "url for this server is not in the disk map";
        $sane = 0;
    }
    
    my %buckets;
    
    foreach my $server (@{ $self->config->{servers} })
    {
      my $name = $server->{url} // 'unknown';
      unless($server->{url})
      {
        say "server $name has no URL";
        $sane = 0;
      }
      if(@{ $server->{disks} } > 0)
      {
        foreach my $disk (@{ $server->{disks} })
        {
          my $name2 = $disk->{root} // 'unknown';
          unless($disk->{root})
          {
            say "server $name disk $name2 has no root";
            $sane = 0;
          }
          if(@{ $disk->{buckets} })
          {
            foreach my $bucket (@{ $disk->{buckets} })
            {
              if($buckets{$bucket})
              {
                say "server $name disk $name2 has duplicate bucket (also seen at $buckets{$bucket})";
                $sane = 0;
              }
              else
              {
                $buckets{$bucket} = "server $name disk $name2";
              }
            }
          }
          else
          {
            say "server $name disk $name2 has no buckets assigned";
            $sane = 0;
          }
        }
      }
      else
      {
        say "server $name has no disks";
        $sane = 0;
      }
    }
    
    $sane;
}

sub generate_config {
    my $self = shift;

    my $root = $ENV{CLUSTERICIOUS_CONF_DIR} || $ENV{HOME};

    return {
     dirs => [
         [qw(etc)],
         [qw(var log)],
         [qw(var run)],
         [qw(var lib yars data)],
     ],
     files => { 'Yars.conf' => <<'CONF', 'log4perl.conf' => <<CONF2 } };
---
% my $root = $ENV{HOME};
start_mode : 'hypnotoad'
url : http://localhost:9999
hypnotoad :
  pid_file : <%= $root %>/var/run/yars.pid
  listen :
     - http://localhost:9999
servers :
- url : http://localhost:9999
  disks :
    - root : <%= $root %>/var/lib/yars/data
      buckets : [ <%= join ',', '0'..'9', 'a' .. 'f' %> ]
CONF
log4perl.rootLogger=TRACE, LOGFILE
log4perl.logger.Mojolicious=TRACE
log4perl.appender.LOGFILE=Log::Log4perl::Appender::File
log4perl.appender.LOGFILE.filename=$root/var/log/yars.log
log4perl.appender.LOGFILE.mode=append
log4perl.appender.LOGFILE.layout=PatternLayout
log4perl.appender.LOGFILE.layout.ConversionPattern=[%d{ISO8601}] [%7Z] %5p: %m%n
CONF2
}

=head1 SEE ALSO

=over 4

=item L<Yars::Client>

Perl API interface to Yars.

=item L<yarsclient>

Command line client interface to Yars.

=item L<Yars::Routes>

HTTP REST routes useable for interfacing with Yars.

=item L<yars_exercise>

Automated upload / download of files to Yars for performance testing.

=item L<Clustericious>

Yars is built on the L<Clustericious> framework, itself heavily utilizing
L<Mojolicious>

=back

=cut

1;
