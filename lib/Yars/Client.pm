package Yars::Client;

# ABSTRACT: Yet Another RESTful-Archive Service Client
# VERSION

use strict;
use warnings;
use 5.010;
use Clustericious::Client;
use Clustericious::Client::Command;
use Clustericious::Config;
use Mojo::Asset::File;
use Mojo::ByteStream 'b';
use Mojo::URL;
use Mojo::Base '-base';
use File::Basename;
use File::Spec;
use Log::Log4perl qw(:easy);
use Digest::file qw/digest_file_hex/;
use Data::Dumper;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use Number::Bytes::Human qw( format_bytes parse_bytes );
use File::Temp qw( tempdir );

route_doc upload   => "<filename>";
route_doc content  => "<filename> <md5>";
route_doc download => "<filename> <md5> [dir]";
route_doc remove   => "<filename> <md5>";

has bucket_map_cached  => sub { 0; }; # Computed on demand.

route 'welcome'        => "GET",  '/';
route 'bucket_map'     => "GET",  '/bucket_map';
route 'disk_usage'     => "GET",  '/disk/usage';
route 'bucket_usage'   => "GET",  '/bucket/usage';
route 'servers_status' => "GET",  '/servers/status';
route 'get'            => "GET",  '/file', \"<md5> <filename>";
route 'check'          => "HEAD", '/file', \"<md5> <filename>";
route 'set_status'     => "POST", '/disk/status';
route 'check_files'    => "POST", '/check/manifest';

route_meta 'welcome'        => { auto_failover => 1, dont_read_files => 1 };
route_meta 'bucket_map'     => { auto_failover => 1, dont_read_files => 1 };
route_meta 'disk_usage'     => { auto_failover => 1, dont_read_files => 1 };
route_meta 'bucket_usage'   => { auto_failover => 1, dont_read_files => 1 };
route_meta 'servers_status' => { auto_failover => 1, dont_read_files => 1 };
route_meta 'get'            => { auto_failover => 1, dont_read_files => 1 };
route_meta 'check'          => { auto_failover => 1, dont_read_files => 1 };
route_meta 'set_status'     => { auto_failover => 1, dont_read_files => 1 };
route_meta 'check_files'    => { auto_failover => 1, dont_read_files => 1 };

route_meta 'upload'         => { dont_read_files => 1 };
route_meta 'download'       => { dont_read_files => 1 };
route_meta 'check_manifest' => { dont_read_files => 1 };
route_meta 'check'          => { dont_read_files => 1 };

route_args send => [
    { name => 'content',  type => '=s', required => 1 },
    { name => 'name',     type => '=s' },
];

route_args retrieve => [
    { name => 'location', type => '=s' },
    { name => 'name',     type => '=s' },
    { name => 'md5',      type => '=s' },
];

sub new {
    my $self = shift->SUPER::new(@_);
    $self->client->max_redirects(30);
    $self->client->connect_timeout(30);
    $self->client->on(start => sub {
      # tx
      $_[1]->req->headers->header('X-Yars-Skip-Verify' => 'on');
    });
    return $self;
}

sub client {
    my($self, $new) = @_;
    
    $new ? do { 
        $new->max_redirects(30);
        $new->connect_timeout(30);
        $self->SUPER::client($new);
        $new;
    } : $self->SUPER::client;
}

sub _get_url {

    # Helper to create the Mojo URL objects
    my ($self, $path) = @_;

    my $url = Mojo::URL->new( $self->server_url );
    $url->path($path) if $path;

    return $url;
}

sub _hex2b64 {
    my $hex = shift or return;
    my $b64 = b(pack 'H*', $hex)->b64_encode;
    local $/="\n";
    chomp $b64;
    return $b64;
}

sub _b642hex {
    my $b64 = shift or return;
    # Mojo::Headers apparently become array refs sometimes
    $b64 = $b64->[0] if ref($b64) eq 'ARRAY';
    return unpack 'H*', b($b64)->b64_decode;
}

sub location {
    my ($self, $filename, $md5) = @_;

    ( $filename, $md5 ) = ( $md5, $filename ) if $filename =~ /^[0-9a-f]{32}$/i;
    LOGDIE "Can't compute location without filename" unless defined($filename);
    LOGDIE "Can't compute location without md5" unless $md5;
    $self->server_url($self->_server_for($md5));
    return $self->_get_url("/file/$md5/$filename")->to_abs->to_string;
}

sub download {
    # Downloads a file and saves it to disk.
    my $self = shift;
    my ( $filename, $md5, $dest_dir ) = @_;
    my $abs_url;
    if (@_ == 1) {
        $abs_url = shift;
        ($filename) = $abs_url =~ m|/([^/]+)$|;
    }
    ( $filename, $md5 ) = ( $md5, $filename ) if $filename =~ /^[0-9a-f]{32}$/i;

    if (!$md5 && !$abs_url) {
        LOGDIE "Need either an md5 or a url: download(url) or download(filename, md5, [dir] )";
    }

    my @hosts;
    @hosts  = $self->_all_hosts($self->_server_for($md5)) unless $abs_url;
    my $tries = 0;
    my $success = 0;
    my $host = 0;
    while ($tries++ < 10) {

        if ($tries > @hosts + 1) {
            TRACE "Attempt $tries";
            WARN "Waiting $tries seconds before retrying...";
            sleep $tries;
        }
        my $url;
        if ($abs_url) {
            $url = $abs_url;
        } else {
            $host = 0 if $host > $#hosts;
            $url = Mojo::URL->new($hosts[$host++]);
            $url->path("/file/$filename/$md5");
        }
        TRACE "GET $url";
        my $tx = $self->client->build_tx(GET => $url, { "Connection" => "Close", "Accept-Encoding" => "gzip" } );
        # TODO: set timeout for mojo 4.0
        $tx->res->max_message_size(parse_bytes($self->_config->max_message_size_client(default => 53687091200)));
        $self->client->start($tx);
        $self->res($tx->res);
        $self->tx($tx);
        my $res = $tx->success or do {
            my ($msg,$code) = $tx->error;
            if ($code) {
                ERROR "$code $msg";
                last;
            }
            if ($msg =~ /connection refused/i) {
                WARN "Error : $msg (may retry)";
                next;
            }
            WARN "Error (may retry) : " . (ref($msg) ? Dumper($msg) : $msg);
            next;
        };
        DEBUG "Received asset with size ".$res->content->asset->size;
        TRACE "Received headers : ".$res->headers->to_string;

        my $out_file = $dest_dir ? $dest_dir . "/$filename" : $filename;
        DEBUG "Writing to $out_file";
        if (my $e = $res->headers->header("Content-Encoding")) {
            LOGDIE "unsupported encoding" unless $e eq 'gzip';
            # This violate the spec (MD5s depend on transfer-encoding
            # not content-encoding, per
            # http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html
            # but we must support it.
            TRACE "unzipping $out_file";
            my $asset = $res->content->asset;
            gunzip($asset->is_file ? $asset->path : \( $asset->slurp )
                 => $out_file) or do {
                unlink $out_file;
                LOGDIE "Gunzip failed : $GunzipError";
            };
        } else {
            $res->content->asset->move_to($out_file);
        }
        my $verify = digest_file_hex($out_file,'MD5');
        $md5 ||= _b642hex($res->headers->header("Content-MD5"));

        unless ($md5) {
            WARN "No md5 in response header";
            next;
        }
        unless ($verify eq $md5) {
            WARN "Bad md5 for file (got $verify instead of $md5)";
            WARN "Response headers : ".$res->headers->to_string;
            unlink $out_file or WARN "couldn't remove $out_file : $!";
            WARN "Removed $out_file.  This is attempt $tries.";
            next;
        }

        $success = 1;
        last;
    }
    ERROR "Download failed." unless $success;
    return '' unless $success;
    return 'ok'; # return TRUE
}

sub remove {
    # Removes a file
    my ( $self, $filename, $md5 ) = @_;

    LOGDIE "file and md5 needed for remove"
        unless $filename && $md5;

    my $url = $self->_get_url("/file/$md5/$filename");
    TRACE("removing $filename $md5 from ", $url->to_string);

    # Delete the file
    $self->_doit(DELETE => $url);
}

# Given an md5, determine the correct server
# using a cached list of bucket->server assignments.
sub _server_for {
    my $self = shift;
    my $md5 = shift or LOGDIE "Missing argument md5";
    my $bucket_map = $self->bucket_map_cached;
    unless ($bucket_map && ref($bucket_map) eq 'HASH' && keys %$bucket_map > 0) {
        $bucket_map = $self->bucket_map or WARN $self->errorstring;
        $self->bucket_map_cached({ %$bucket_map }) if $bucket_map && ref $bucket_map && (keys %$bucket_map > 0);
    }
    unless ($bucket_map && ref $bucket_map && (keys %$bucket_map > 0)) {
        WARN "Failed to retrieve bucket map, using ".$self->server_url;
        return $self->server_url;
    }
    for (0..length($md5)) {
        my $prefix = substr($md5,0,$_);
        return $bucket_map->{ lc $prefix } if exists($bucket_map->{lc $prefix});
        return $bucket_map->{ uc $prefix } if exists($bucket_map->{uc $prefix});
    }
    LOGDIE "Can't find url for $md5 in bucket map : ".Dumper($bucket_map);
}

sub put {
    my $self = shift;
    my $remote_filename = shift;
    my $content = shift || join '', <STDIN>;
    # NB: slow for large content.
    my $md5 = b($content)->md5_sum;
    my $url = Mojo::URL->new($self->_server_for($md5));
    $url->path("/file/$remote_filename");
    TRACE "PUT $url";
    my $tx = $self->client->put("$url" => { "Content-MD5" => _hex2b64($md5), "Connection" => "Close" } => $content);
    $self->res($tx->res);
    $self->tx($tx);
    return $tx->success ? 'ok' : '';
}

sub _all_hosts {
    my $self = shift;
    my $assigned = shift;
    # Return all the hosts, any parameter will be put first in
    # the list.
    my @servers = ($assigned);
    push @servers, $self->server_url;
    push @servers, $self->_config->url;
    push @servers, @{ $self->_config->failover_urls(default => []) };
    my %seen;
    return grep { !$seen{$_}++ } @servers;
}

sub upload {
    my $self = shift;
    my $content = ref($_[-1]) eq 'SCALAR' ? pop : undef;
    my $filename = pop;
    my $nostash;
    if (@_) {
        # To avoid failover :
        # yarsclient upload --nostash 1 foo
        # $yc->upload("--nostash",1","foo")
        # This is undocumented since it is only intended to be
        # used on a server when balancing, not as a public interface.

        if ($_[0] =~ /nostash$/) {
            shift;
            $nostash = shift;
        }
    }
    if (@_) {
        LOGDIE "unknown options to upload : @_";
    }

    LOGDIE "file needed for upload" unless $filename;
    if(defined $content) {
        # intended mainly for testing only,
        # may be ulsewise later
        $filename = File::Spec->catfile( tempdir( CLEANUP => 1 ), $filename );
        open my $fh, '>', $filename;
        binmode $fh;
        print $fh $$content;
        close $fh;
    } else {
        $filename = File::Spec->rel2abs($filename);
    }
    -r $filename or LOGDIE "Could not read " . $filename;

    # Don't read the file.
    my $basename = basename($filename);
    my $asset    = Mojo::Asset::File->new( path => $filename );
    my $md5      = digest_file_hex($filename, 'MD5');

    my @servers = $self->_all_hosts( $self->_server_for($md5) );

    my $tx;
    my $code;
    my $host;

    while (!$code && ($host = shift @servers)) {
        my $url = Mojo::URL->new($host);
        $url->path("/file/$basename/$md5");
        DEBUG "Sending $md5 to $url";

        my @nostash = ($nostash ? ("X-Yars-NoStash" => 1) : ());
        $tx = $self->client->build_tx(
            PUT => "$url" => {
                @nostash,
                "Content-MD5" => _hex2b64($md5),
                "Connection"  => "Close"
            }
        );
        $tx->req->content->asset($asset);
        # TODO: set timeout for mojo 4.0
        $tx = $self->client->start($tx);
        $code = $tx->res->code;
        $self->res($tx->res);
        $self->tx($tx);

        if (!$tx->success) {
            my ($msg,$code) = $tx->error;
            if ($code) {
                INFO "Failed to PUT to $host : $code $msg";
            } else {
                INFO "PUT to $host failed : ".$msg;
            }
        }
    }
    return '' if !$code || !$tx->res->is_status_class(200);

    DEBUG "Response : ".$tx->res->code." ".$tx->res->message;
    $self->res($tx->res);
    return 'ok';
}

sub _rand_filename {
    my $a = '';
    $a .= ('a'..'z','A'..'Z',0..9)[rand 62] for 1..43;
    return $a;
}

sub send {
    my $self = shift;
    my $meta = $self->meta_for;
    my %args = $meta->process_args(@_);
    my $content = $args{content};
    my $filename = $args{name} || $self->_rand_filename;
    my $status = $self->put($filename, $content);
    return unless $status eq 'ok';
    return $self->res->headers->location;
}

sub retrieve {
    my $self = shift;
    my %args = $self->meta_for->process_args(@_);
    if (my $location = $args{location}) {
        my $tx = $self->client->get($location);
        my $res = $tx->success or do {
            $self->tx($tx);
            $self->res($tx->res);
            return;
        };
        return $res->body;
    }
    my $md5 = $args{md5} or LOGDIE "need md5 or location to retrieve";
    my $name = $args{name} or LOGDIE "need name or location to retrieve";
    return $self->get($md5,$name);
}

sub res_md5 {
    my $self = shift;
    my $res = $self->res or return;
    if (my $b64 = $res->headers->header("Content-MD5")) {
        return _b642hex($b64);
    }
    if (my $location = $res->headers->location) {
        my ($md5) = $location =~ m[/file/([0-9a-f]{32})/];
        return $md5;
    }
    return;
}

sub check_manifest {
    my $self     = shift;
    my @args     = @_;
    my $check    = 0;
    my $params  = "";
    my $manifest;
    while ($_ = shift @_) {
        /^-c$/ and do { $check = 1; next; };
        /^--show_corrupt$/ and do { $params = "?show_corrupt=" . shift; next; };
        $manifest = $_;
    }
    LOGDIE "Missing manifest" unless $manifest;
    LOGDIE "Cannot open manifest $manifest" unless -e $manifest;
    my $contents = Mojo::Asset::File->new(path => $manifest)->slurp;
    my $got      = $self->_doit(POST => "/check/manifest$params", { manifest => $contents  });
    return $got unless $self->tx->success;
    $got->{$manifest} = (@{$got->{missing}}==0 ? 'ok' : 'not ok');
    return { $manifest => $got->{$manifest} } if $check;
    return $got;
}

sub remote {
    my $self = shift;
    $self->bucket_map_cached(0);
    $self->SUPER::remote(@_);
}

1;

__END__

=head1 SYNOPSIS

 my $r = Yars::Client->new;

 # Send and retrieve content.
 my $location = $y->send(content => 'hello, world') or die $y->errorstring;
 say $y->retrieve(location => $location);

 # Alternatively, use names and md5s explicitly.
 my $location = $y->send(content => 'hello there', name => "greeting");
 my $md5 = $y->res_md5;
 say $y->retrieve(filename => 'greeting', md5 => $md5);

 # Upload a file.
 $r->upload($filename) or die $r->errorstring;
 print $r->res->headers->location;

 # Download a file.
 $r->download($filename, $md5) or die $r->errorstring;
 $r->download($filename, $md5, '/tmp');   # download it to the /tmp directory
 $r->download("http://yars/0123456890abc/filename.txt"); # Write filename.txt to current directory.

 # More concise version of retrieve.
 my $content = $r->get($filename,$md5);

 # Delete a file.
 $r->remove($filename, $md5) or die $r->errorstring;

 # Compute the URL of a file based on the md5 and the buckets.
 print $r->location($filename, $md5);

 print "Server version is ".$r->status->{server_version};
 my $usage = $r->disk_usage();      # Returns usage for a single server.
 my $nother_usage = Yars::Client->new(url => "http://host1:9999")->disk_usage();
 my $status = $r->servers_status(); # return a hash of servers, disks, and their statuses

 # Mark a disk down.
 my $ok = $r->set_status({ root => "/acps/disk/one", state => "down" });
 my $ok = $r->set_status({ root => "/acps/disk/one", state => "down", host => "http://host2" });

 # Mark a disk up.
 my $ok = $r->set_status({ root => "/acps/disk/one", state => "up" });

 # Check a manifest file or list of files.
 my $details = $r->check_manifest( $filename );
 my $check = $r->check_manifest( "-c", $filename );
 my $check = $r->check_manifest( "--show_corrupt" => 1, $filename );
 my $ck = $r->check_files({ files => [
     { filename => $f1, md5 => $m1 },
     { filename => $f2, md5 => $m2 } ] });


=head1 DESCRIPTION

Client for L<Yars>.

=head1 SEE ALSO

L<yarsclient>, L<Clustericious::Client>

=cut
