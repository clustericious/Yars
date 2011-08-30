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
use File::Temp;
use Clustericious::RouteBuilder;

# max downloads of 1 GB
$ENV{MOJO_MAX_MESSAGE_SIZE} = 1073741824;

our $DataDir;
$DataDir = File::Temp->newdir( UNLINK => 1 ) if $ENV{HARNESS_ACTIVE};

ladder sub { $DataDir ||= shift->config->data_dir; };

# Calculate the location of a file on disk.
sub _dir {
    my $digest = shift;
    my @clumps = ( grep length, split /(...)/, $digest );
    return join "/", $DataDir, @clumps;
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

    # send the URL back in the header
    my $location = $c->url_for("file", md5 => $digest, filename => $filename)->to_abs;
    $c->res->headers->location($location);

    if (-e "$dir/$filename") {
        # file exits - render ok
        $c->render(status => 200, text => 'ok');
    }
    else {
        # create the file - use a temp file for atomicity
        my $tmp = File::Temp->new( UNLINK => 0, DIR => $dir );
        print $tmp $content;
        $tmp->close;
        rename "$tmp", "$dir/$filename" or die "rename failed: $!";
        $c->render(status => 201, text => 'created');
    }
};


Delete '/file/(.filename)/:md5' => [ md5 => qr/[a-z0-9]{32}/ ] => sub {
    my $c        = shift;
    my $dir      = _dir( $c->stash("md5") );
    my $filename = $c->stash('filename');

    return $c->render_not_found unless -r "$dir/$filename";
    if ( unlink "$dir/$filename" ) {
        $c->render(status => 200, text =>'ok'); 
    }
    else {
        $c->render_exception;
    }
};

1;
