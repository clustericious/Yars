# Yars [![Build Status](https://secure.travis-ci.org/plicease/Yars.png)](http://travis-ci.org/plicease/Yars)

Yet Another RESTful-Archive Service

# SYNOPSIS

Create a configuration in ~/etc/Yars.conf

    ---
    url: http://localhost:9001
    start_mode: hypnotoad
    hypnotoad:
      pid_file: <%= home %>/var/run/yars.pid
      listen: [ 'http://localhost:9001' ]
    servers:
      - url: http://localhost:9001
        disks:
          - root: <%= home %>/var/data/disk1
            buckets: <%= json [ 0..9, 'a'..'f' ] %>

Create needed directories and run the server

    % mkdir -p ~/var/run ~/var/data/disk1
    % yars start

Upload a file:

    % md5sum foo.jog
    469f9b131cce1631ddd449fbef9059ba  foo.jpg
    % yarsclient upload foo.jpg

Download a file

    % yarsclient download foo.jpg 469f9b131cce1631ddd449fbef9059ba

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

The configuration file is a [Mojo::Template](https://metacpan.org/pod/Mojo::Template) template with
helpers provided by [Clustericious::Config::Helpers](https://metacpan.org/pod/Clustericious::Config::Helpers).

Create the directories needed for the server:

    % mkdir -p ~/var/run ~/var/data

Now you can start the server process

    % yars start

### check status

Now verify that it works:

    % curl http://localhost:9001/status
    {"server_url":"http://localhost:9001","server_version":"1.11","app_name":"Yars","server_hostname":"iscah"}

You can also verify that it works with [yarsclient](https://metacpan.org/pod/yarsclient):

    % yarsclient status
    ---
    app_name: Yars
    server_hostname: iscah
    server_url: http://localhost:9001
    server_version: '1.11'

Or via [Yars::Client](https://metacpan.org/pod/Yars::Client):

    % perl -MYars::Client -MYAML::XS=Dump -E 'say Dump(Yars::Client->new->status)'
    ---
    app_name: Yars
    server_hostname: iscah
    server_url: http://localhost:9001
    server_version: '1.11'

### upload and downloads

Now try storing a file:

    % echo "hi" | curl -D headers.txt -T - http://localhost:9001/file/test_file1
    ok
    % grep Location headers.txt 
    Location: http://localhost:9001/file/764efa883dda1e11db47671c4a3bbd9e/test_file1

You can use the Location header to fetch the file at a later time

    % curl http://localhost:9001/file/764efa883dda1e11db47671c4a3bbd9e/test_file1
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

### set up the URL

When configuring a cluster of several hosts, the `url` value
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

A less tedious way is to use the `hostname` or `hostname_full`
helper from [Clustericious::Config::Helpers](https://metacpan.org/pod/Clustericious::Config::Helpers).  This allows you
to use the same configuration for all servers in the cluster:

    ---
    # works for yars1, yars2 but not for
    # a client host
    url: http://<%= hostname %>:9001

### abstract the webserver configuration

If you have multiple [Clustericious](https://metacpan.org/pod/Clustericious) services on the same host,
or if you share configurations between multiple hosts, it may be
useful to use the <%= extends\_config %> helper and put the web
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

Now if you were also going to use [PlugAuth](https://metacpan.org/pod/PlugAuth) on the same host
they could share the same `hypnotoad.conf` file with different
parameters:

    ---
    # ~/etc/PlugAuth.conf
    % my $url = "http://" . hostname . ":3001";
    url: <%= $url %>
    % extends_config 'hypnotoad', url => $url, name => 'plugauth';

### generate the disk map

Given a file with a list of hosts and disks like this called diskmap.txt:

    yars1 /disk/1a
    yars1 /disk/1b
    yars2 /disk/2a
    yars2 /disk/2b
    yars3 /disk/3a
    yars3 /disk/3b

You can generate a disk map using the [yars\_generate\_diskmap](https://metacpan.org/pod/yars_generate_diskmap) command:

    % yars_generate_diskmap 2 diskmap.txt > ~/etc/yars_diskmap.conf

This will generate a diskmap configuration with the buckets evenly 
allocated to the available disks:

    ---
    servers :
    - url : http://yars1:9001
      disks :
      - root : /disk/1a
        buckets : [ 00, 06, 0c, 12, 18, 1e, 24, 2a, 30, 36, 3c, 42, 48,
                    4e, 54, 5a, 60, 66, 6c, 72, 78, 7e, 84, 8a, 90, 96, 9c,
                    a2, a8, ae, b4, ba, c0, c6, cc, d2, d8, de, e4, ea, f0,
                    f6, fc ]
      - root : /disk/1b
        buckets : [ 01, 07, 0d, 13, 19, 1f, 25, 2b, 31, 37, 3d, 43, 49,
                    4f, 55, 5b, 61, 67, 6d, 73, 79, 7f, 85, 8b, 91, 97, 9d,
                    a3, a9, af, b5, bb, c1, c7, cd, d3, d9, df, e5, eb, f1,
                    f7, fd ]
    - url : http://yars2:9001
      disks :
      - root : /disk/2a
        buckets : [ 02, 08, 0e, 14, 1a, 20, 26, 2c, 32, 38, 3e, 44, 4a,
                    50, 56, 5c, 62, 68, 6e, 74, 7a, 80, 86, 8c, 92, 98, 9e,
                    a4, aa, b0, b6, bc, c2, c8, ce, d4, da, e0, e6, ec, f2,
                    f8, fe ]
      - root : /disk/2b
        buckets : [ 03, 09, 0f, 15, 1b, 21, 27, 2d, 33, 39, 3f, 45, 4b,
                    51, 57, 5d, 63, 69, 6f, 75, 7b, 81, 87, 8d, 93, 99, 9f,
                    a5, ab, b1, b7, bd, c3, c9, cf, d5, db, e1, e7, ed, f3,
                    f9, ff ]
    - url : http://yars3:9001
      disks :
      - root : /disk/3a
        buckets : [ 04, 0a, 10, 16, 1c, 22, 28, 2e, 34, 3a, 40, 46, 4c,
                    52, 58, 5e, 64, 6a, 70, 76, 7c, 82, 88, 8e, 94, 9a, a0,
                    a6, ac, b2, b8, be, c4, ca, d0, d6, dc, e2, e8, ee, f4,
                    fa ]
      - root : /disk/3b
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

Also, if for whatever reason you are unable to use the `hostname`
or `hostname_full` helper in your `Yars.conf` file, it helps to
keep your diskmap configuration in a separate file that can be shared
between the different Yars server configuration files.

You can now run `yars start` on each host to start the servers.
[clad](https://metacpan.org/pod/clad) may be useful for starting "yars start" on multiple hosts
at once.

### client configuration

If you are using the `hostname` or `hostname_full` helpers to
generate the URL in the serve configuration, then you won't be
able to share that configuration with client systems.  In addition
you can specify one or more failover hosts for [Yars::Client](https://metacpan.org/pod/Yars::Client)
and `yarsclient` to use when the primary is not available:

    ---
    # ~/etc/Yars.conf on client systems
    url: http://yars2:9001
    failover_urls:
      - http://yars1:9001

## Accelerated downloads with nginx

One of the advantages of Clustericious is that it integrates with
a number of different webservers.  You can do testing with hypnotoad,
which comes with [Mojolicious](https://metacpan.org/pod/Mojolicious) (and thus a prerequisite of 
[Clustericious](https://metacpan.org/pod/Clustericious) and Yars), and then deploy to production with a
more capable webserver, such as nginx.  The integration with nginx
allows for handing off some of the workload to nginx; hypnotoad is
good for serving dynamic web apps, but nginx is better for serving
static files.  So with this next configuration we will show you
how to configure Yars to handle the selection of servers and disks
and hand off the actual serving of the static file to nginx.

Once again we put the nginx configuration in its own file so that
we can reuse it with other [Clustericious](https://metacpan.org/pod/Clustericious) services.

    ---
    # ~/etc/nginx.conf
    start_mode:
      - hypnotoad
      - nginx
    
    # we use hypnotoad to server the dynamic part of the app
    # and listen to the same port on localhost
    hypnotoad:
      listen:
        - http://127.0.0.1:<%= $port %>
      pid_file: <%= home %>/var/run/<%= $name %>-hypnotoad.pid
      proxy: 1
    
    # and we proxy requests on the main IP address through
    # nginx
    nginx:
      '-p': <%= home %>/var/run/<%= $name %>-nginx
      '-c': <%= home %>/var/run/<%= $name %>-nginx/conf/nginx.conf
      autogen:
        filename: <%= home %>/var/run/<%= $name %>-nginx/conf/nginx.conf
        content: |
            # autogenerated file
            events {
              worker_connections 4096;
            }
            http {
              server {
                listen <%= hostname %>:<%= $port %>;
                location / {
                  proxy_pass http://127.0.0.1:<%= $port %>;
                  proxy_http_version 1.1;
    % if($name eq 'yars') {
                  # to accelerate downloads, for Yars only
                  # we set the X-Yars-Use-X-Accel header to
                  # any value.  This will trigger Yars to
                  # use nginx's X-Accel-Redirect to serve
                  # actual static files back to the client.
                  proxy_set_header X-Yars-Use-X-Accel yes;
    % }
                }
    % if($name eq 'yars') {
                # we need to make the static files available
                # to nginx.  The /static prefix is to ensure
                # that routes (future and present) do not
                # conflict with physical files on your disk.
                location /static/disk/ {
                  # internal makes sure that these files
                  # won't be served to external clients
                  # without going through the yars interface
                  internal;
                  alias /disk/;
                }
    % }
              }
            }

and once again, our `Yars.conf` file is short and sweet:

    ---
    % my $port = 9001;
    url: http://<%= hostname %>:<%= $port %>
    % extends_config 'nginx', port => $port, name => 'yars';
    % extends_config 'yars_diskmap';

## Accelerate by not checking the md5 twice

By default, Yars checks the MD5 of files before serving
them to the client.  [Yars::Client](https://metacpan.org/pod/Yars::Client) and [yarsclient](https://metacpan.org/pod/yarsclient) both
also check the MD5 sum after downloading.  This saves
bandwidth if automated processes attempt to redownload the
same file if it is corrupted on the disk of the server.
The chance of error is likely much higher on the network
than it is on the disk, and if you prefer to do the check
just on the client side, then you can use set the
download\_md5\_verify to zero.

    ---
    % my $port = 9001;
    url: http://<%= hostname %>:<%= $port %>
    % extends_config 'nginx', port => $port, name => 'yars';
    % extends_config 'yars_diskmap';
    download_md5_verify: 0

When you download files with other clients like `curl` or
`wget`, the MD5 check will still happen on the server
side.  You may request this check be skipped by setting
the `X-Yars-Skip-Verify` header to any value.

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
