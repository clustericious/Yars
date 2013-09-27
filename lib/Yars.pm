package Yars;

use strict;
use warnings;
use Mojo::Base 'Clustericious::App';
use Yars::Routes;
use Yars::Tools;
use Mojo::ByteStream qw/b/;
use File::Path qw/mkpath/;
use Log::Log4perl qw(:easy);
use Number::Bytes::Human qw( format_bytes parse_bytes );

# ABSTRACT: Yet Another RESTful-Archive Service
our $VERSION = '0.90'; # VERSION


has secret => rand;


sub _mojo4_compat {
    my $self = shift;
    $self->hook(before_dispatch => sub {
        my($c) = @_;
        my $stream = Mojo::IOLoop->stream($c->tx->connection);
        return unless defined $stream;
        $stream->timeout(3000);
    });
}

sub startup {
    my $self = shift;

    if ($Mojolicious::VERSION >= 4.0) {
        $self->_mojo4_compat;
    #} elsif ($Mojolicious::VERSION >= 2.37) {
    } else {
        eval { Mojo::IOLoop::Stream->timeout(3000) };
        if(my $error = $@) {
            WARN "error trying to set timeout: $@";
            WARN "Mojolicious version $Mojolicious::VERSION";
            WARN "Will try Mojo 4.x mode";
            $self->_mojo4_compat;
        }
    }

    my $max_size = 53687091200;

    my $tools;

    $self->hook(
        after_build_tx => sub {
            my ( $tx, $app ) = @_;
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
                            my ( $mem, $file ) = @_;
                            $file->tmpdir($tmpdir);
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


1;

__END__
=pod

=head1 NAME

Yars - Yet Another RESTful-Archive Service

=head1 VERSION

version 0.90

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

=head1 EXAMPLE 1

The following sequence of commands will start yars on
a single host (with 16 buckets) :

    $ mkdir ~/etc
    $ cat > ~/etc/Yars.conf
    ---
    start_mode : 'hypnotoad'
    url : http://localhost:9999
    hypnotoad :
      pid_file : /tmp/yars.pid
      listen :
         - http://localhost:9999
    servers :
    - url : http://localhost:9999
      disks :
        - root : /usr/local/data/disk1
          buckets : [ <%= join ',', '0'..'f' %> ]
    ^D

    $ yars start

Now, verify that it works :

    $ GET http://localhost:9999/status

And try to PUT and GET a file :

    echo "hi" | lwp-request -em PUT http://localhost:9999/file/here
    # (notice the "Location" header
    GET http://localhost:9999/file/764efa883dda1e11db47671c4a3bbd9e/here

Also you can use L<Yars::Client> :

    echo "hi" > myfile
    yarsclient upload myfile
    yarsclient download myfile 764efa883dda1e11db47671c4a3bbd9e

Or to see the requests and responses :

    yarsclient --trace root upload myfile
    yarsclient --trace root download myfile 764efa883dda1e11db47671c4a3bbd9e

=head1 EXAMPLE 2

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

=head2 startup

Called by the server to start up, we change
the object classes to use Yars::Message::Request
for incoming requests.

=head1 SEE ALSO

L<Yars::Client>

=head1 AUTHOR

original author: Marty Brandon

current maintainer: Graham Ollis <plicease@cpan.org>

contributors:

Brian Duggan

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by NASA GSFC.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

