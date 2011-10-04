=head1 NAME

Yars::Tools -- various utility functions dealing with servers, hosts, etc

=head1 DESCRIPTION

Just some useful functions here.

=head1 FUNCTIONS

=over

=cut

package Yars::Tools;
use Clustericious::Config;
use List::Util qw/shuffle/;
use List::MoreUtils qw/uniq/;
use Log::Log4perl qw/:easy/;
use File::Find::Rule;
use File::Basename qw/dirname/;
use Data::Dumper;
use Try::Tiny;
use File::Path qw/mkpath/;
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
 return 1 if defined($OurUrl) && keys %Bucket2Root > 0;
 $config ||= Clustericious::Config->new("Yars");
 $OurUrl = $config->url or WARN "No url found in config file";
 TRACE "Our url is $OurUrl";
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
 TRACE "bucket2url : ".Dumper(\%Bucket2Url);
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
    unless (keys %Bucket2Root) {
        $class->refresh_config;
        LOGDIE "No config data" unless keys %Bucket2Root > 0;
    }
    TRACE "no local disk for $digest in ".(join ' ', keys %Bucket2Root) unless defined($bucket);
    return unless defined($bucket);
    return $Bucket2Root{$bucket};
}

our %diskStatusCache;
our $diskStatusCacheLifetime = 3;

=item disk_is_up

Given a disk root, return true unless the disk is marked down.
A disk may be marked down in several ways.  If the root is
/mnt/archive/f0002 then any of the following will indicate
that the disk is down and should not be written to :

    1. /mnt/archive/f0002 is not writeable.
    2. The file /mnt/archive/f0002.is_down exists.
    3. The file /mnt/archive/f0002/is_down exists.

The ability to mark it down in several ways is designed
to allow one to mark it as down without using a central
mechanism, and without relying on being able to write
to the disk.

=cut

sub disk_is_up {
    my $class = shift;
    my $root = shift;
    # TODO (tests fail)
    #if (exists($diskStatusCache{$root}) && $diskStatusCache{$root}{checked} > time - $diskStatusCacheLifetime) {
    #    return $diskStatusCache{$root}{result};
    #}
    $diskStatusCache{$root}{checked} = time;
    return ($diskStatusCache{$root}{result} = 0) if ( -d $root && ! -w $root);
    return ($diskStatusCache{$root}{result} = 0) if -e "$root.is_down";
    return ($diskStatusCache{$root}{result} = 0) if -e "$root/is_down";
    return ($diskStatusCache{$root}{result} = 1);
}

=item disk_is_down

Disk is not up.

=cut

sub disk_is_down {
    return not shift->disk_is_up(@_);
}

=item disk_is_local

Return true iff the disk is on this server.

=cut

sub disk_is_local {
    my $class = shift;
    my $root = shift;
    return $DiskIsLocal{$root};
}

=item server_is_up, server_is_down

Check to see if a remote server is up or down.

=cut

our $UA;
our %serverStatusCache;
our $serverStatusCacheLifetime = 3; # cache results for three seconds
sub server_is_up {
    my $class = shift;
    my $server_url = shift;
    if (exists($serverStatusCache{$server_url}) && $serverStatusCache{$server_url}{checked} > time - $serverStatusCacheLifetime) {
        return $serverStatusCache{$server_url}{result};
    }
    $UA ||= Mojo::UserAgent->new;
    TRACE "Checking $server_url/status";
    my $tx = $UA->get( "$server_url/status" );
    $serverStatusCache{$server_url}{checked} = time;
    if (my $res = $tx->success) {
        my $got = $res->json;
        if (defined($got->{server_version}) && length($got->{server_version})) {
            return ($serverStatusCache{$server_url}{result} = 1);
        }
    }
    TRACE "No version from $server_url/status";
    return ($serverStatusCache{$server_url}{result} = 0);
}
sub server_is_down {
    return not shift->server_is_up(@_);
}

sub _touch {
    my $path = shift;
    my $dir = dirname($path);
    -d $dir or do {
        my $ok;
        try { mkpath($dir); $ok = 1; }
        catch { WARN "mkpath $dir failed : $_;"; $ok = 0; };
        return 0 unless $ok;
    };
    open my $fp, ">>$path" or return 0;
    close $fp;
    return 1;
}

=item mark_disk_down, mark_disk_up

Mark a disk as up or down.

=cut

sub mark_disk_down {
    my $class = shift;
    my $root = shift;
    return 1 if $class->disk_is_down($root);
    _touch("$root.is_down") and return 1;
    _touch("$root/is_down") and return 1;
    -d $root and do { chmod 0555, $root and return 1; };
    ERROR "Could not mark disk $root down";
    return 0;
}

sub mark_disk_up {
    my $class = shift;
    my $root = shift;
    return 1 if $class->disk_is_up($root);
    -d $root and ! -w $root and do {
        chmod 0775, $root or WARN "chmod $root failed : $!";
    };
    -e "$root.is_down" and do { unlink "$root.is_down" or WARN "unlink $root.is_down failed : $!"; };
    -e "$root/is_down" and do { unlink "$root/is_down" or WARN "unlink $root/is_down failed : $!"; };
    return $class->disk_is_up($root);
}

=item server_for

Given an md5, return the url for the server for this file.

=cut

sub server_for {
    my $class = shift;
    my $digest = shift;
    my $found;
    for my $i (0..length($digest)) {
        last if $found = $Bucket2Url{ uc substr($digest,0,$i) };
        last if $found = $Bucket2Url{ lc substr($digest,0,$i) };
    }
    return $found;
}

=item bucket_map

Return a map from bucket prefix to server url.

=cut

sub bucket_map {
    return \%Bucket2Url;
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
Returns :
    The directory or false.

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

=item disk_roots

Return all the local directory roots, in a random order.

=cut

sub disk_roots {
    return keys %DiskIsLocal;
}

=item server_urls

Return all the other urls, in a random order.

=cut

sub server_urls {
    return keys %Servers;
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
    -d $dir or return 0;
    my @list = File::Find::Rule->file->not_name("is_down")->in($dir);
    return scalar @list;
}

=item human_size

Given a size, format it like df -kh

=cut

sub human_size {
    my $class = shift;
    my $val   = shift;
    my @units = qw/B K M G T P/;
    my $unit = shift @units;
    do {
        $unit = shift @units;
        $val /= 1024;
    } until $val < 1024 || !@units;
    return sprintf( "%.0f%s", $val + 0.5, $unit );
}


1;

