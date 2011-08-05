package Yars::Routes;

=head1 NAME

Yars::Routes -- set up the routes for Yars.

=head1 DESCRIPTION

This package creates all the routes, and thus defines
the API for Yars.

=head1 TODO

Optimize lookups.  Currently we match prefixes
so that a heterogenous set of prefixes can be
supported (e.g. "1", "2", "30", "31"..)

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
# These could be optimized by using Data::Trie
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

sub _disk_for {
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

sub _dir {
    # Calculate the location of a file on disk.
    # Optionally pass a second parameter to force it onto a particular disk.
    my $digest = shift;
    my $root = shift || _disk_for($digest) || LOGCONFESS "No local disk for $digest";
    return join "/", $root, ( grep length, split /(..)/, $digest );
}

get '/' => sub { shift->render_text("welcome to Yars") } => 'index';

get '/file/(.filename)/:md5' => [ md5 => qr/[a-z0-9]{32}/ ] => \&_get;
get '/file/:md5/(.filename)' => [ md5 => qr/[a-z0-9]{32}/ ] => \&_get => "file";
sub _get {
    my $c        = shift;
    my $filename = $c->stash("filename");
    my $md5      = $c->stash("md5");

    my $url = _server_for($md5);
    unless ($url eq $OurUrl) {
        TRACE "$md5 should be on $url";
        # but check our local stash first, just in case.
        return _get_from_local_stash($c,$filename,$md5) || $c->redirect_to($url);
    }

    my $dir = _dir($md5);
    -r "$dir/$filename" or do {
        return
             _get_from_local_stash( $c, $filename, $md5 )
          || _get_from_remote_stash( $c, $filename, $md5 )
          || $c->render_not_found;
    };
    $c->app->static->root($dir)->serve($c,$filename);
    $c->rendered;
};

sub _get_from_local_stash {
    my ($c,$filename,$md5) = @_;
    # If this is stashed locally, render it and return.
    # Otherwise return false.
    for my $root ( shuffle keys %DiskIsLocal ) {
        my $dir = _dir($md5,$root);
        TRACE "Checking for $dir/$filename";
        next unless -r "$dir/$filename";
        TRACE "Found $dir/$filename";
        $c->app->static->root($dir)->serve($c,$filename);
        $c->rendered;
        return 1;
    }
    return 0;
}

sub _get_from_remote_stash {
    # If this is stored somewhere else return a redirect header.
    # broadcast a HEAD
    # TODO
    LOGDIE "not implemented : get from remote stash";
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

    if (_atomic_write( _dir($digest), $filename, $content ) ) {
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
        ERROR "Could not write $dir/$filename : $_";
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
    my $assigned_root = _disk_for($digest);
    my $wrote;
    for my $root ( shuffle keys %DiskIsLocal ) {
        next if $assigned_root && ($root eq $assigned_root);
        my $dir = _dir( $digest, $root );
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

del '/file/(.filename)/:md5' => [ md5 => qr/[a-z0-9]{32}/ ] => sub {
    my $c        = shift;
    my $dir      = _dir( $c->stash("md5") );
    my $filename = $c->stash('filename');

    -r "$dir/$filename" or return $c->render_not_found;
    unlink "$dir/$filename" or return $c->render_exception($!);

    $c->render(status => 200, text =>'ok');
};

1;
