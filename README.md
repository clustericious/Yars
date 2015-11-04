# Yars [![Build Status](https://secure.travis-ci.org/plicease/Yars.png)](http://travis-ci.org/plicease/Yars)

Yet Another RESTful-Archive Service

# DESCRIPTION

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
the aid of an included tool, [yars\_generate\_diskmap](https://metacpan.org/pod/yars_generate_diskmap)).

The server is controlled with the command line tool [yars](https://metacpan.org/pod/yars).

The basic operations of a running yars cluster are supporting
requests of the form

    PUT http://$host/file/$filename
    GET http://$host/file/$md5/$filename
    HEAD http://$host/file/$md5/$filename
    GET http://$host/bucket_map

to store and retrieve files, where $host may be any of the
hosts in the cluster, $md5 is the md5 of the content, and
$filename is a filename for the content to be stored.  See
[Yars::Routes](https://metacpan.org/pod/Yars::Routes) for documentation of other routes.

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

Another tool [yars\_fast\_balance](https://metacpan.org/pod/yars_fast_balance) is provided which takes
files from stashes and returns them to their correct
locations.

A client [Yars::Client](https://metacpan.org/pod/Yars::Client) is also available (in a separate
distribution), for interacting with a yars server.

# EXAMPLES

## simple single server configuration

This creates a single Yars server using hypnotoad with sixteen buckets.

Create a configuration file in `~/etc/Yars.conf` with this
content:

    ---
    
    # The first half of the configuration specifies the
    # generic Clustericious / web server settings for
    # the server
    start_mode : 'hypnotoad'
    url : http://localhost:9999
    hypnotoad :
      pid_file : <%= home %>/var/run/yars.pid
      listen :
         - http://localhost:9999
    
    # The rest defines the servers, disks and buckets
    # used by the Yars cluster.  In this single server
    # example, there is only one server and one disk
    servers :
    - url : http://localhost:9999
      disks :
        - root : <%= home %>/var/data/disk1
          buckets : <%= json [ 0..9, 'a'..'f' ] %>

The configuration file is a [Mojo::Template](https://metacpan.org/pod/Mojo::Template) template with
helpers provided by [Clustericious::Config::Helpers](https://metacpan.org/pod/Clustericious::Config::Helpers).

Create the directories needed for the server:

    % mkdir -p ~/var/run ~/var/data

Now you can start the server process

    % yars start

### check status

Now verify that it works:

    % curl http://localhost:9999/status
    {"server_url":"http://localhost:9999","server_version":"1.11","app_name":"Yars","server_hostname":"iscah"}

You can also verify that it works with [yarsclient](https://metacpan.org/pod/yarsclient):

    % yarsclient status
    ---
    app_name: Yars
    server_hostname: iscah
    server_url: http://localhost:9999
    server_version: '1.11'

Or via [Yars::Client](https://metacpan.org/pod/Yars::Client):

    % perl -MYars::Client -MYAML::XS=Dump -E 'say Dump(Yars::Client->new->status)'
    ---
    app_name: Yars
    server_hostname: iscah
    server_url: http://localhost:9999
    server_version: '1.11'

### upload and downloads

Now try storing a file:

    % echo "hi" | curl -D headers.txt -T - http://localhost:9999/file/test_file1
    ok
    % grep Location headers.txt 
    Location: http://localhost:9999/file/764efa883dda1e11db47671c4a3bbd9e/test_file1

You can use the Location header to fetch the file at a later time

    % curl http://localhost:9999/file/764efa883dda1e11db47671c4a3bbd9e/test_file1
    hi

With [yarsclient](https://metacpan.org/pod/yarsclient)

    % echo "hi" > test_file2
    % md5sum test_file2
    764efa883dda1e11db47671c4a3bbd9e  test_file2
    % yarsclient upload test_file2
    
    ... some time later ...
    
    % yarsclient downbload test_file2 764efa883dda1e11db47671c4a3bbd9e

You can see the HTTP requests and responses using the `--trace` option:

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

## Multiple hosts

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

See also, [clad](https://metacpan.org/pod/clad), for a tool to facilitate
running "yars start" on multiple hosts at once.

## Accelerated downloads with nginx

TODO

# SEE ALSO

- [Yars::Client](https://metacpan.org/pod/Yars::Client)

    Perl API interface to Yars.

- [yarsclient](https://metacpan.org/pod/yarsclient)

    Command line client interface to Yars.

- [Yars::Routes](https://metacpan.org/pod/Yars::Routes)

    HTTP REST routes useable for interfacing with Yars.

- [yars\_exercise](https://metacpan.org/pod/yars_exercise)

    Automated upload / download of files to Yars for performance testing.

- [Clustericious](https://metacpan.org/pod/Clustericious)

    Yars is built on the [Clustericious](https://metacpan.org/pod/Clustericious) framework, itself heavily utilizing
    [Mojolicious](https://metacpan.org/pod/Mojolicious)

# AUTHOR

Original author: Marty Brandon

Current maintainer: Graham Ollis &lt;plicease@cpan.org>

Contributors:

Brian Duggan

Curt Tilmes

# COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by NASA GSFC.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
