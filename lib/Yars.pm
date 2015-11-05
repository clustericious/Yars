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

Failover is handled in the following manner:

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
 
 # The first half of the configuration specifies the
 # generic Clustericious / web server settings for
 # the server
 start_mode : 'hypnotoad'
 url : http://localhost:9001
 hypnotoad :
   pid_file : <%= home %>/var/run/yars.pid
   listen :
      - http://localhost:9001
 
 # The rest defines the servers, disks and buckets
 # used by the Yars cluster.  In this single server
 # example, there is only one server and one disk
 servers :
 - url : http://localhost:9001
   disks :
     - root : <%= home %>/var/data/disk1
       buckets : <%= json [ 0..9, 'a'..'f' ] %>

The configuration file is a L<Mojo::Template> template with
helpers provided by L<Clustericious::Config::Helpers>.

Create the directories needed for the server:

 % mkdir -p ~/var/run ~/var/data

Now you can start the server process

 % yars start

=head3 check status

Now verify that it works:

 % curl http://localhost:9001/status
 {"server_url":"http://localhost:9001","server_version":"1.11","app_name":"Yars","server_hostname":"iscah"}

You can also verify that it works with L<yarsclient>:

 % yarsclient status
 ---
 app_name: Yars
 server_hostname: iscah
 server_url: http://localhost:9001
 server_version: '1.11'

Or via L<Yars::Client>:

 % perl -MYars::Client -MYAML::XS=Dump -E 'say Dump(Yars::Client->new->status)'
 ---
 app_name: Yars
 server_hostname: iscah
 server_url: http://localhost:9001
 server_version: '1.11'

=head3 upload and downloads

Now try storing a file:

 % echo "hi" | curl -D headers.txt -T - http://localhost:9001/file/test_file1
 ok
 % grep Location headers.txt 
 Location: http://localhost:9001/file/764efa883dda1e11db47671c4a3bbd9e/test_file1

You can use the Location header to fetch the file at a later time

 % curl http://localhost:9001/file/764efa883dda1e11db47671c4a3bbd9e/test_file1
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

=head3 set up the URL

When configuring a cluster of several hosts, the C<url> value
in the configuration must have the correct hostname or IP
address for each host that the server is running on.  One
way to handle this would be to have a configuration file for
each host:

 ---
 # ~/etc/Yars.conf on yars1
 url: http://yars1:9001

 ---
 # ~/etc/Yars.conf on yars2
 url: http://yars2:9001

A less tedious way is to use the C<hostname> or C<hostname_full>
helper from L<Clustericious::Config::Helpers>.  This allows you
to use the same configuration for all servers in the cluster:

 ---
 # works for yars1, yars2 but not for
 # a client host
 url: http://<%= hostname %>:9001

=head3 abstract the webserver configuration

If you have multiple L<Clustericious> services on the same host,
or if you share configurations between multiple hosts, it may be
useful to use the <%= extends_config %> helper and put the web
server configuration in a separate file.  For example:

 ---
 # ~/etc/Yars.conf
 % my $url = "http://" . hostname . ":9001";
 url: <%= $url %>
 % extends_config 'hypnotoad', url => $url, name => 'yars';

 ---
 # ~/etc/hypnotoad.conf
 hypnotoad :
   pid_file : <%= home %>/var/run/<%= $name %>.pid
   listen :
      - <%= $url %>

Now if you were also going to use L<PlugAuth> on the same host
they could share the same C<hypnotoad.conf> file with different
parameters:

 ---
 # ~/etc/PlugAuth.conf
 % my $url = "http://" . hostname . ":3001";
 url: <%= $url %>
 % extends_config 'hypnotoad', url => $url, name => 'plugauth';

=head3 generate the disk map

Given a file with a list of hosts and disks like this called diskmap.txt:

 yars1 /disk1a
 yars1 /disk1b
 yars2 /disk2a
 yars2 /disk2b
 yars3 /disk3a
 yars3 /disk3b

You can generate a disk map using the L<yars_generate_diskmap> command:

 % yars_generate_diskmap 2 diskmap.txt > ~/etc/yars_diskmap.conf

This will generate a diskmap configuration with the buckets evenly 
allocated to the available disks:

 ---
 servers :
 - url : http://yars1:9001
   disks :
   - root : /disk1a
     buckets : [ 00, 06, 0c, 12, 18, 1e, 24, 2a, 30, 36, 3c, 42, 48,
                 4e, 54, 5a, 60, 66, 6c, 72, 78, 7e, 84, 8a, 90, 96, 9c,
                 a2, a8, ae, b4, ba, c0, c6, cc, d2, d8, de, e4, ea, f0,
                 f6, fc ]
   - root : /disk1b
     buckets : [ 01, 07, 0d, 13, 19, 1f, 25, 2b, 31, 37, 3d, 43, 49,
                 4f, 55, 5b, 61, 67, 6d, 73, 79, 7f, 85, 8b, 91, 97, 9d,
                 a3, a9, af, b5, bb, c1, c7, cd, d3, d9, df, e5, eb, f1,
                 f7, fd ]
 - url : http://yars2:9001
   disks :
   - root : /disk2a
     buckets : [ 02, 08, 0e, 14, 1a, 20, 26, 2c, 32, 38, 3e, 44, 4a,
                 50, 56, 5c, 62, 68, 6e, 74, 7a, 80, 86, 8c, 92, 98, 9e,
                 a4, aa, b0, b6, bc, c2, c8, ce, d4, da, e0, e6, ec, f2,
                 f8, fe ]
   - root : /disk2b
     buckets : [ 03, 09, 0f, 15, 1b, 21, 27, 2d, 33, 39, 3f, 45, 4b,
                 51, 57, 5d, 63, 69, 6f, 75, 7b, 81, 87, 8d, 93, 99, 9f,
                 a5, ab, b1, b7, bd, c3, c9, cf, d5, db, e1, e7, ed, f3,
                 f9, ff ]
 - url : http://yars3:9001
   disks :
   - root : /disk3a
     buckets : [ 04, 0a, 10, 16, 1c, 22, 28, 2e, 34, 3a, 40, 46, 4c,
                 52, 58, 5e, 64, 6a, 70, 76, 7c, 82, 88, 8e, 94, 9a, a0,
                 a6, ac, b2, b8, be, c4, ca, d0, d6, dc, e2, e8, ee, f4,
                 fa ]
   - root : /disk3b
     buckets : [ 05, 0b, 11, 17, 1d, 23, 29, 2f, 35, 3b, 41, 47, 4d,
                 53, 59, 5f, 65, 6b, 71, 77, 7d, 83, 89, 8f, 95, 9b, a1,
                 a7, ad, b3, b9, bf, c5, cb, d1, d7, dd, e3, e9, ef, f5,
                 fb ]

which you can now extend from the Yars.conf file:

 ---
 # ~/etc/Yars.conf
 % my $url = "http://" . hostname . ":9001";
 url: <%= $url %>
 % extends_config 'hypnotoad', url => $url, name => 'yars';
 % extends_config 'yars_diskmap';

Also, if for whatever reason you are unable to use the C<hostname>
or C<hostname_full> helper in your C<Yars.conf> file, it helps to
keep your diskmap configuration in a separate file that can be shared
between the different Yars server configuration files.

You can now run C<yars start> on each host to start the servers.
L<clad> may be useful for starting "yars start" on multiple hosts
at once.

=head3 client configuration

If you are using the C<hostname> or C<hostname_full> helpers to
generate the URL in the serve configuration, then you won't be
able to share that configuration with client systems.  In addition
you can specify one or more failover hosts for L<Yars::Client>
and C<yarsclient> to use when the primary is not available:

 ---
 # ~/etc/Yars.conf on client systems
 url: http://yars2:9001
 failover_urls:
   - http://yars1:9001

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
url : http://localhost:9001
hypnotoad :
  pid_file : <%= $root %>/var/run/yars.pid
  listen :
     - http://localhost:9001
servers :
- url : http://localhost:9001
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
