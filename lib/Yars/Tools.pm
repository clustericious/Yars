=head1 NAME

Yars::Tools -- various utility functions dealing with servers, hosts, etc

=head1 DESCRIPTION

Just some useful functions here.

=head1 FUNCTIONS

=over

=cut

package Yars::Tools;
use List::Util qw/shuffle/;
use List::MoreUtils qw/uniq/;
use Log::Log4perl qw/:easy/;
use File::Find::Rule;
use Data::Dumper;
use strict;
use warnings;

our %Bucket2Url;  # map buckets to server urls
our %Bucket2Root; # map buckets to disk roots
our $OurUrl;      # Our server url
our %DiskIsLocal; # Our disk roots (values are just 1)
our %Servers;     # All servers

=item refresh_config

Refresh the configuration data cached in memory.

=cut

sub refresh_config {
 my $class = shift;
 my $config = shift;
 return 1 if defined($OurUrl);
 $OurUrl = $config->url;
 for my $server ($config->servers) {
    $Servers{$server->{url}} = 1;
    for my $disk (@{ $server->{disks} }) {
        for my $bucket (@{ $disk->{buckets} }) {
            $Bucket2Url{$bucket} = $server->{url};
            next unless $server->{url} eq $OurUrl;
            $Bucket2Root{$bucket} = $disk->{root};
            LOGDIE "Disk root not given" unless defined($disk->{root});
            $DiskIsLocal{$disk->{root}} = 1;
        }
    }
 }
 TRACE "bucket map : ".Dumper(\%Bucket2Url);
}

sub _dir_is_empty {
    # stolen from File::Find::Rule::DirectoryEmpty
    my $dir = shift;
    opendir( DIR, $dir ) or return;
    for ( readdir DIR ) {
        if ( !/^\.\.?$/ ) {
            closedir DIR;
            return 0;
        }
    }
    closedir DIR;
    return 1;
}

=item disk_for

Given an md5 digest, calculate the root directory of this file.
Undef is returned if this file does not belong on the current host.

=cut

sub disk_for {
    my $class = shift;
    my $digest = shift;
    my ($bucket) = grep { $digest =~ /^$_/i } keys %Bucket2Root;
    WARN "Could not find disk for $digest in ".(join ' ', keys %Bucket2Root) unless defined($bucket);
    return unless defined($bucket);
    return $Bucket2Root{$bucket};
}

=item server_for

Given an md5, return the url for the server for this file.

=cut

sub server_for {
    my $class = shift;
    my $digest = shift;
    my ($bucket) = grep { $digest =~ /^$_/i } keys %Bucket2Url;
    return $Bucket2Url{$bucket};
}

=item storage_path

Calculate the directory of an md5 on disk.
Optionally pass a second parameter to force it onto a particular disk.

=cut

sub storage_path {
    my $class = shift;
    my $digest = shift;
    my $root = shift || $class->disk_for($digest) || LOGCONFESS "No local disk for $digest";
    return join "/", $root, ( grep length, split /(..)/, $digest );
}

=item remote_stashed_server

Find a server which is stashing this file, if one exists.
Parameters :
    $c - controller
    $filename - filename
    $digest - digest

=cut

sub remote_stashed_server {
    my $class = shift;
    my ($c,$filename,$digest) = @_;

    my $assigned_server = Yars::Tools->server_for($digest);
    # TODO broadcast these requests all at once
    for my $server (shuffle keys %Servers) {
        next if $server eq $OurUrl;
        next if $server eq $assigned_server;
        DEBUG "Checking remote $server for $filename";
        my $tx = $c->ua->head( "$server/file/$filename/$digest", { "X-Yars-Check-Stash" => 1 } );
        if (my $res = $tx->success) {
            # Found it!
            return $server;
        }
    }
    return '';
}

=item local_stashed_dir

Find a local directory stashing this file, if one exists.
Parameters :
    $filename - filename
    $digest - digest


=cut

sub local_stashed_dir {
    my $class = shift;
    my ($filename,$md5) = @_;
    for my $root ( shuffle keys %DiskIsLocal ) {
        my $dir = Yars::Tools->storage_path($md5,$root);
        TRACE "Checking for $dir/$filename";
        return $dir if -r "$dir/$filename";
    }
    return '';
}

=item server_url

Returns the url of the current server.

=cut

sub server_url {
    return $OurUrl;
}

=item shuffled_disk_roots

Return all the local directory roots, in a random order.

=cut

sub shuffled_disk_roots {
    return shuffle keys %DiskIsLocal;
}

=item shuffled_server_urls

Return all the other urls, in a random order.

=cut

sub shuffled_server_urls {
    return shuffle keys %Servers;
}

=item cleanup_tree

Given a direcory, traverse upwards until encountering
a local disk root or a non-empty directory, and remove
all empty dirs.

=cut

sub cleanup_tree {
    my $class = shift;
    my ($dir) = @_;
    while (_dir_is_empty($dir)) {
        last if $DiskIsLocal{$dir};
        rmdir $dir or do { warn "cannot rmdir $dir : $!"; last; };
        $dir =~ s[/[^/]+$][];
     }
}

=item count_files

Count the number of files in a directory tree.

=cut

sub count_files {
    my $class = shift;
    my $dir = shift;
    my @list = File::Find::Rule->file->in($dir);
    return scalar @list;
}


1;

