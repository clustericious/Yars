package Yars::Routes;

=head1 NAME

Yars::Routes -- set up the routes for Yars.

=head1 DESCRIPTION

This package creates all the routes, and thus defines
the API for Yars.

=cut

use strict;
use warnings;
use Mojo::ByteStream qw/b/;
use Log::Log4perl qw/:easy/;
use File::Path qw/mkpath/;
use List::MoreUtils qw/uniq/;
use File::Temp;
use Clustericious::RouteBuilder;

# max downloads of 1 GB
$ENV{MOJO_MAX_MESSAGE_SIZE} = 1073741824;

our %OurBuckets;  # indicates which buckets are on this server
our %Bucket2Root; # map buckets to disk roots
ladder sub {
 my $c = shift;
 return 1 if keys %OurBuckets > 0;
 my @buckets = map @{ $_->{buckets} },
      grep { $_->{url} eq $c->config->url } $c->config->servers;
 LOGDIE "No buckets assigned." unless @buckets > 0;
 %OurBuckets = map { $_ => 1 } @buckets;
 for my $disk ($c->config->disks) {
    for my $bucket (@{ $disk->{buckets} }) {
        next unless $OurBuckets{$bucket};
        $Bucket2Root{$bucket} = $disk->{root};
    }
 }
 TRACE "Our buckets : @buckets";
 TRACE "Our disks : ".join ' ', uniq values %Bucket2Root;
 return 1;
};

# Calculate the location of a file on disk.
sub _dir {
    my $digest = shift;
    my ($key) = grep { $digest =~ /^$_/i } keys %Bucket2Root;
    my $root = $Bucket2Root{$key} or LOGDIE "no dir for $digest on this server";
    my @clumps = ( grep length, split /(...)/, $digest );
    return join "/", $root, @clumps;
}

get '/' => sub { shift->render_text("welcome to Yars") } => 'index';

get '/file/(.filename)/:md5' => [ md5 => qr/[a-z0-9]{32}/ ] => \&_get;
get '/file/:md5/(.filename)' => [ md5 => qr/[a-z0-9]{32}/ ] => \&_get => "file";
sub _get {
    my $c        = shift;
    my $dir      = _dir( $c->stash("md5") );
    my $filename = $c->stash("filename");
    return $c->render_not_found unless -r "$dir/$filename";
    $c->app->static->root($dir)->serve($c,$filename);
    $c->rendered;
};

put '/file/(.filename)/:md5' => { md5 => 'none' } => sub {
    my $c        = shift;
    my $filename = $c->stash('filename');
    my $md5      = $c->stash('md5');
    my $content  = $c->req->body;
    my $digest = b($content)->md5_sum->to_string;

    return $c->render(text => "incorrect digest, $md5!=$digest", status => 400)
        if ( $md5 ne 'none' and $digest ne $md5 );

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


Delete '/file/(.filename)/:md5' => [ md5 => qr/[a-z0-9]{32}/ ] => sub {
    my $c        = shift;
    my $dir      = _dir( $c->stash("md5") );
    my $filename = $c->stash('filename');

    -r "$dir/$filename" or return $c->render_not_found;
    unlink "$dir/$filename" or return $c->render_exception($!);

    $c->render(status => 200, text =>'ok');
};

1;
