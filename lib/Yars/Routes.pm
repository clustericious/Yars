package Yars::Routes;

=head1 NAME

Yars::Routes -- set up the routes for Yars.

=head1 DESCRIPTION

This package defines the API for Yars.

=head1 TODO

Optimize lookups.  Currently we match prefixes
so that a heterogenous set of prefixes can be
supported (e.g. "1", "2", "30", "31"..), Data::Trie
may be useful.

=cut

use strict;
use warnings;
use Mojo::ByteStream qw/b/;
use Log::Log4perl qw/:easy/;
use File::Path qw/mkpath/;
use List::Util qw/shuffle/;
use List::MoreUtils qw/uniq/;
use File::Temp;
use Clustericious::RouteBuilder;
use Try::Tiny;
use Data::Dumper;

# max downloads of 1 GB
$ENV{MOJO_MAX_MESSAGE_SIZE} = 1073741824;

our %Bucket2Url;  # map buckets to server urls
our %Bucket2Root; # map buckets to disk roots
our $OurUrl;      # Our server url
our %DiskIsLocal; # Our disk roots (values are just 1)
our %Servers;     # All servers
ladder sub {
 my $c = shift;
 return 1 if defined($OurUrl);
 $OurUrl = $c->config->url;
 for my $server ($c->config->servers) {
    $Servers{$server->{url}} = 1;
    for my $disk (@{ $server->{disks} }) {
        for my $bucket (@{ $disk->{buckets} }) {
            $Bucket2Url{$bucket} = $server->{url};
            next unless $server->{url} eq $OurUrl;
            $Bucket2Root{$bucket} = $disk->{root};
            $DiskIsLocal{$disk->{root}} = 1;
        }
    }
 }
 TRACE "bucket map : ".Dumper(\%Bucket2Url);

 return 1;
};

# TODO move this elsewhere
sub disk_for {
    # Given an md5 digest, calculate the root directory of this file.
    # Undef is returned if this file does not belong on the current host.
    my $digest = shift;
    my ($bucket) = grep { $digest =~ /^$_/i } keys %Bucket2Root;
    return $Bucket2Root{$bucket};
}

sub _server_for {
    # Given an md5, return the url for the server for this file.
    my $digest = shift;
    my ($bucket) = grep { $digest =~ /^$_/i } keys %Bucket2Url;
    return $Bucket2Url{$bucket};
}

sub storage_path {
    # Calculate the location of a file on disk.
    # Optionally pass a second parameter to force it onto a particular disk.
    my $digest = shift;
    my $root = shift || disk_for($digest) || LOGCONFESS "No local disk for $digest";
    return join "/", $root, ( grep length, split /(..)/, $digest );
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

get '/' => sub { shift->render_text("welcome to Yars") } => 'index';

get  '/file/(.filename)/:md5' => [ md5 => qr/[a-z0-9]{32}/ ] => \&_get;
get  '/file/:md5/(.filename)' => [ md5 => qr/[a-z0-9]{32}/ ] => \&_get => "file";
sub _get {
    my $c        = shift;
    my $filename = $c->stash("filename");
    my $md5      = $c->stash("md5");

    return _head($c, @_) if $c->req->method eq 'HEAD';

    my $url = _server_for($md5);
    if ($url ne $OurUrl) {
        TRACE "$md5 should be on $url";
        # but check our local stash first, just in case.
        _get_from_local_stash($c,$filename,$md5) and return;
        return $c->redirect_to("$url/file/$md5/$filename");
    }

    my $dir = storage_path($md5);
    -r "$dir/$filename" or do {
        return
             _get_from_local_stash( $c, $filename, $md5 )
          || _redirect_to_remote_stash( $c, $filename, $md5 )
          || $c->render_not_found;
    };
    $c->app->static->root($dir)->serve($c,$filename);
    $c->rendered;
};

sub _head {
    my $c        = shift;
    my $filename = $c->stash("filename");
    my $md5      = $c->stash("md5");

    if ($c->req->headers->header("X-Yars-Check-Stash")) {
        if (_local_stashed_dir($filename,$md5)) {
            return $c->render(status => 200, text => 'found');
        }
        return $c->render_not_found;
    }

    # Otherwise mimick GET, but just check for existence.
    my $url = _server_for($md5);
    if ($url ne $OurUrl) {
        TRACE "$md5 should be on $url";
        # but check our local stash first, just in case.
        if (_local_stashed_dir($filename,$md5)) {
            return $c->render(status => 200, text => 'found');
        }
        return $c->redirect_to("$url/file/$md5/$filename");
    }

    my $dir = storage_path($md5);

    if ( -r "$dir/$filename"
        or _local_stashed_dir($filename,$md5)
        or _remote_stashed_server($c, $filename,$md5)) {
            return $c->render(status => 200, text => 'found');
    }
    $c->render_not_found;
}

sub _local_stashed_dir {
    my ($filename,$md5) = @_;
    for my $root ( shuffle keys %DiskIsLocal ) {
        my $dir = storage_path($md5,$root);
        TRACE "Checking for $dir/$filename";
        return $dir if -r "$dir/$filename";
    }
    return '';
}

sub _get_from_local_stash {
    my ($c,$filename,$md5) = @_;
    # If this is stashed locally, serve it and return true.
    # Otherwise return false.
    my $dir = _local_stashed_dir($filename,$md5) or return 0;
    $c->app->static->root($dir)->serve($c,$filename);
    $c->rendered;
    return 1;
}

sub _remote_stashed_server {
    my ($c,$filename,$digest) = @_;
    # Find a server which is stashing this file, if one exists.

    my $assigned_server = _server_for($digest);
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

sub _redirect_to_remote_stash {
    my ($c,$filename,$digest) = @_;
    DEBUG "Checking remote stashes";
    if (my $server = _remote_stashed_server($c,$filename,$digest)) {
        return $c->redirect_to("$server/file/$digest/$filename");
    };
    return 0;
}


put '/file/(.filename)/:md5' => { md5 => 'calculate' } => sub {
    my $c        = shift;
    my $filename = $c->stash('filename');
    my $md5      = $c->stash('md5');
    my $content  = $c->req->body;
    my $digest   = b($content)->md5_sum->to_string;
    $md5 = $digest if $md5 eq 'calculate';

    return $c->render(text => "incorrect digest, $md5!=$digest", status => 400)
            if $digest ne $md5;

    if ($c->req->headers->header('X-Yars-Stash')) {
        DEBUG "Stashing a file that is not ours here on $OurUrl : $digest $filename";
        _stash_locally($c, $filename, $digest, $content) and return;
        return $c->render_exception("Cannot stash $filename locally");
    }

    my $assigned_server = _server_for($digest);

    if ( $assigned_server ne $OurUrl ) {
        return _proxy_to( $c, $assigned_server, $filename, $digest, $content )
              || _stash_locally( $c, $filename, $digest, $content )
              || _stash_remotely( $c, $filename, $digest, $content )
              || $c->render_exception("could not proxy or stash");
    }

    DEBUG "Received $filename on $OurUrl";

    if (_atomic_write( storage_path($digest), $filename, $content ) ) {
        # Normal situation.
        my $location = $c->url_for("file", md5 => $digest, filename => $filename)->to_abs;
        $c->res->headers->location($location);
        return $c->render(status => 201, text => 'ok'); # CREATED
    }

    # Local designated disk is down.
    _stash_locally( $c, $filename, $digest, $content )
      or _stash_remotely( $c, $filename, $digest, $content )
      or $c->render_exception("could not store or stash remotely");
};

sub _proxy_to {
    my ($c, $url,$filename,$digest,$content,$temporary) = @_;
    # Proxy a file to another url.
    # On success, render the response and return true.
    # On failure, return false.
   my $res;
   DEBUG "Proxying file $filename with md5 $digest to $url/file/$filename/$digest"
      . ( $temporary ? " temporarily" : "" );
   my $headers = $temporary ? { 'X-Yars-Stash' => 1 } : {};
   $headers->{Connection} = "Close";
   my $tx = $c->ua->put( "$url/file/$filename/$digest", $headers, $content );
   if ($res = $tx->success) {
       $c->res->headers->location($tx->res->headers->location);
       $c->render(status => $tx->res->code, text => 'ok');
       return 1;
   }
   my ($message, $code) = $tx->error;
   ERROR "failed to proxy $filename to $url : $message".($code ? " code $code" : "");
   return 0;
}

sub _atomic_write {
    my ($dir, $filename, $content) = @_;
    # Write a file atomically.  Return 1 on success, 0 on failure.
    my $failed;
    try {
        mkpath $dir; # dies on error
        my $tmp = File::Temp->new( UNLINK => 0, DIR => $dir )
          or LOGDIE "Cannot make tempfile in $dir : $!";
        print $tmp $content or LOGDIE "Cannot write content in $dir : $!";
        $tmp->close or LOGDIE "cannot close tempfile";
        rename "$tmp", "$dir/$filename" or LOGDIE "rename failed: $!";
    } catch {
        WARN "Could not write $dir/$filename : $_";
        $failed = 1;
    };
    return 0 if $failed;
    TRACE "Wrote $dir/$filename";
    return 1;
}

sub _stash_locally {
    my ($c, $filename,$digest, $content) = @_;
    # Stash this file on a local disk.
    # Returns false or renders the response.
    DEBUG "Stashing $filename locally";
    my $assigned_root = disk_for($digest);
    my $wrote;
    for my $root ( shuffle keys %DiskIsLocal ) {
        next if $assigned_root && ($root eq $assigned_root);
        my $dir = storage_path( $digest, $root );
        _atomic_write( $dir, $filename, $content ) and do {
            $wrote = $root;
            last;
        };
    }
    WARN "Help, all my disks are unwriteable!" unless $wrote;
    # I'm not dead yet!  It's only a flesh wound!
    return 0 unless $wrote;
    my $location = $c->url_for("file", md5 => $digest, filename => $filename)->to_abs;
    $c->res->headers->location($location);
    $c->render(status => 201, text => 'ok'); # CREATED
    DEBUG "Stashed $filename ($digest) locally on $wrote";
    return 1;
}

sub _stash_remotely {
    my ($c, $filename,$digest,$content) = @_;
    # Stash this file on a remote disk.
    # Returns false or renders the response.
    DEBUG "Stashing $filename remotely.";
    my $assigned_server = _server_for($digest);
    for my $server (shuffle keys %Servers) {
        next if $server eq $OurUrl;
        next if $server eq $assigned_server;
        _proxy_to( $c, $server, $filename, $digest, $content, 1 ) and return 1;
    }
    return 0;
}

del '/file/(.filename)/:md5' => [ md5 => qr/[a-z0-9]{32}/ ] => \&_del;
del '/file/:md5/(.filename)' => [ md5 => qr/[a-z0-9]{32}/ ] => \&_del;

sub cleanup_tree {
    my ($dir) = @_;
    while (_dir_is_empty($dir)) {
        last if $DiskIsLocal{$dir};
        rmdir $dir or do { warn "cannot rmdir $dir : $!"; last; };
        $dir =~ s[/[^/]+$][];
     }
}

sub _del {
    my $c        = shift;
    my $md5      = $c->stash("md5");
    my $filename = $c->stash('filename');
    TRACE "Delete request for $filename, $md5";

    # Delete locally or proxy the delete if it is stashed somewhere else.

    my $server = _server_for($md5);
    if ($server eq $OurUrl) {
        DEBUG "This is our file, we will delete it.";
        my $dir  = storage_path( $md5 );
        if (-r "$dir/$filename" || ($dir = _local_stashed_dir($c,$md5,$filename))) {
            unlink "$dir/$filename" or return $c->render_exception($!);
            cleanup_tree($dir);
            return $c->render(status => 200, text =>'ok');
        }

        $server = _remote_stashed_server($c,$md5,$filename);
        return $c->render_not_found unless $server;
        # otherwise fall through...
    }

    DEBUG "Proxying delete to $server";
    my $tx = $c->ua->delete("$server/file/$md5/$filename");
    if (my $res = $tx->success) {
        return $c->render(status => 200, text => "ok");
    } else  {
        my ($msg,$code) = $tx->error;
        return $c->render_exception("Error deleting from $server ".$tx->error);
    }
};

1;
