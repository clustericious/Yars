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
use List::MoreUtils qw/uniq/;
use File::Temp;
use Clustericious::RouteBuilder;
use Data::Dumper;

# max downloads of 1 GB
$ENV{MOJO_MAX_MESSAGE_SIZE} = 1073741824;

our %Bucket2Url;  # map buckets to server urls
our %Bucket2Root; # map buckets to disk roots
our $OurUrl;      # Our server url
# These could be optimized by using Data::Trie
ladder sub {
 my $c = shift;
 return 1 if defined($OurUrl);
 $OurUrl = $c->config->url;
 for my $server ($c->config->servers) {
    for my $bucket (@{ $server->{buckets} }) {
        $Bucket2Url{$bucket} = $server->{url};
    }
 }
 for my $disk ($c->config->disks) {
    for my $bucket (@{ $disk->{buckets} }) {
        next unless $Bucket2Url{$bucket} eq $OurUrl;
        $Bucket2Root{$bucket} = $disk->{root};
    }
 }
 TRACE "bucket map : ".Dumper(\%Bucket2Url);

 return 1;
};

# Calculate the location of a file on disk.
sub _dir {
    my $digest = shift;
    my ($bucket) = grep { $digest =~ /^$_/i } keys %Bucket2Root;
    my $root = $Bucket2Root{$bucket} or LOGDIE "no dir for $digest on this server";
    my @clumps = ( grep length, split /(...)/, $digest );
    return join "/", $root, @clumps;
}

get '/' => sub { shift->render_text("welcome to Yars") } => 'index';

get '/file/(.filename)/:md5' => [ md5 => qr/[a-z0-9]{32}/ ] => \&_get;
get '/file/:md5/(.filename)' => [ md5 => qr/[a-z0-9]{32}/ ] => \&_get => "file";
sub _get {
    my $c        = shift;
    my $filename = $c->stash("filename");
    my $md5      = $c->stash("md5");

    my ($bucket) = grep { $md5 =~ /^$_/i } keys %Bucket2Url;
    my $url = $Bucket2Url{$bucket};
    unless ($url eq $OurUrl) {
        TRACE "$md5 is on $url";
        return $c->redirect_to($url);
    }

    my $dir = _dir($md5);
    return $c->render_not_found unless -r "$dir/$filename";
    $c->app->static->root($dir)->serve($c,$filename);
    $c->rendered;
};

put '/file/(.filename)/:md5' => { md5 => 'none' } => sub {
    my $c        = shift;
    my $filename = $c->stash('filename');
    my $md5      = $c->stash('md5');
    my $content  = $c->req->body;
    my $digest   = b($content)->md5_sum->to_string;

    return $c->render(text => "incorrect digest, $md5!=$digest", status => 400)
        if ( $md5 ne 'none' and $digest ne $md5 );

    my ($bucket) = grep { $digest =~ /^$_/i } keys %Bucket2Url;
    my $dest = $Bucket2Url{$bucket};
    unless ($dest eq $OurUrl) {
        DEBUG "Proxying file $filename with md5 $digest (bucket $bucket) to file/$dest/$filename/$digest";
        my $tx = $c->ua->put( "$dest/file/$filename/$digest", {}, $content );
        unless ($tx->success) {
              my ($message, $code) = $tx->error;
              ERROR "failed to proxy (status $code) : $message";
              return;
        }
        $c->res->headers->location($tx->res->headers->location);
        $c->render(status => $tx->res->code, text => 'ok');
        return;
    }
    DEBUG "Accepting $filename in bucket $bucket to $dest";

    my $dir = _dir($digest);
    mkpath $dir;

    # use a temp file for atomicity
    my $tmp = File::Temp->new( UNLINK => 0, DIR => $dir );
    print $tmp $content;
    $tmp->close;
    rename "$tmp", "$dir/$filename" or die "rename failed: $!";
    TRACE "Wrote $dir/$filename";

    # send the URL back in the header
    my $location = $c->url_for("file", md5 => $digest, filename => $filename)->to_abs;
    $c->res->headers->location($location);
    $c->render(status => 201, text => 'ok'); # CREATED
};


del '/file/(.filename)/:md5' => [ md5 => qr/[a-z0-9]{32}/ ] => sub {
    my $c        = shift;
    my $dir      = _dir( $c->stash("md5") );
    my $filename = $c->stash('filename');

    -r "$dir/$filename" or return $c->render_not_found;
    unlink "$dir/$filename" or return $c->render_exception($!);

    $c->render(status => 200, text =>'ok');
};

1;
