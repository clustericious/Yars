=head1 NAME

Yars::Balancer

=head1 DESCRIPTION

This starts an asynchronous balancer that is responsible for
sending any stashed files onto their correct host/disk.
The two jobs are :
    1. Locally move any files that are on the wrong disk.
    2. Send away any files that should not be on this host.

The following configuration parameters affect balancers :

balance_delay (10) : the interval (in seconds) between which
a balancer will check for stashed files.  Files will not
be transferred more frequently than this interval.

max_balancers (1): The maximum number of daemons to run as
balancers.  e.g. under hypnotoad + nginx there may be
multiple daemons handling requests.  This parameter
restricts the number that will also balance stashed files.

=head1 TODO

Maybe use inotify instead of periodically checking
with File::Find.

=over

=cut

package Yars::Balancer;
use Yars;
use Mojo::Base qw/-base/;
use List::Util qw/max/;
use Log::Log4perl qw/:easy/;
use Mojo::IOLoop;
use File::Find qw/find/;
use Try::Tiny;
use File::Path qw/mkpath/;
use Fcntl qw(:DEFAULT :flock);
use File::Copy qw/move/;
use File::Basename qw/dirname basename/;
use Cwd qw/getcwd/;

has 'app';

# Move a maximum of one file at time per unix process.
my $file_being_moved;
my $md5_being_moved;

sub _tidy_stashed_files {
    my $disk = shift;
    return if $file_being_moved;
    -d $disk->{root} or return;
    my @belong = @{ $disk->{buckets} };
    TRACE "Checking disk ".$disk->{root};

    # Find the first file that doesn't belong here.
    try {
        local $SIG{__DIE__};
        find(
            {
                no_chdir => 1,
                wanted   => sub {
                    my $dir = $File::Find::dir;
                    $dir =~ s/$disk->{root}//;
                    $dir =~ s[/][]g;
                    my $md5 = $dir;
                    if (grep { $dir =~ /^$_/i } (@belong,'tmp')) {
                        $File::Find::prune = 1;
                        return;
                    }
                    return unless -f;
                    my $destination_server = Yars::Tools->server_for($md5);
                    WARN "No server for $md5" unless $destination_server;
                    if ($destination_server eq Yars::Tools->server_url) {
                        return if Yars::Tools->disk_is_down(Yars::Tools->disk_for($md5));
                    } else {
                        return if Yars::Tools->server_is_down($destination_server);
                    }
                    TRACE "Found first hit $_";
                    $file_being_moved = $_;
                    $md5_being_moved = $md5;
                    die "found\n";
                  }
            },
            $disk->{root}
        );
    } catch {
        $file_being_moved = '' unless $_ eq "found\n";
        WARN $_ unless $_ eq "found\n";
    };
    return unless $file_being_moved;
    DEBUG "Ready to move $file_being_moved ($md5_being_moved)";

    open my $fh, ">> $file_being_moved" or do {
        TRACE "Cannot open $file_being_moved";
        return;
    };
    flock($fh, LOCK_EX | LOCK_NB ) or do {
        TRACE "Not handling $file_being_moved since it is flocked";
        close $fh;
        return;
    };
    if (my $destination_disk = Yars::Tools->disk_for($md5_being_moved)) {
        my $destination_dir = Yars::Tools->storage_path($md5_being_moved, $destination_disk);
        LOGDIE "internal error, already on $destination_disk " if $file_being_moved =~ /^$destination_disk/;
        Mojo::IOLoop->timer( 0 => sub {
            TRACE "Moving $file_being_moved to $destination_disk";
            my $failed;
            try {
                mkpath $destination_dir;
                move $file_being_moved, "$destination_dir" or die $!;
            } catch {
                ERROR "Could not move $file_being_moved to $destination_dir : $_";
                -f "$destination_dir/$file_being_moved" and unlink "$destination_dir/$file_being_moved";
                -d $destination_dir and Yars::Tools->cleanup_tree($destination_dir);
                flock $fh, LOCK_UN;
                $failed = 1;
            };
            DEBUG "Moved file $file_being_moved to $destination_dir" unless $failed;
            undef $file_being_moved;
            undef $md5_being_moved;
            return if $failed;
        });
        return;
    }

    # Otherwise it's a remote file.
    if (my $destination_server = Yars::Tools->server_for($md5_being_moved)) {
        our $UA;
        $UA ||= Mojo::UserAgent->new();
        $UA->ioloop(Mojo::IOLoop->singleton);
        my $name = basename($file_being_moved);
        TRACE "Putting stashed file $name to $destination_server";
        my $url = "$destination_server/file/$name/$md5_being_moved";
        my $tx = $UA->build_tx(PUT => $url,
             { 'X-Yars-NoStash' => 1, 'Content-MD5' => Yars::Tools->hex2b64($md5_being_moved)} );
        $tx->req->content->asset(Mojo::Asset::File->new(path => $file_being_moved));
        $UA->start($tx => sub {
                my ($ua,$tx) = @_;
                if ( my $res = $tx->success ) {
                    TRACE "Successfully put $name to $destination_server";
                    unlink $file_being_moved or
                        WARN "Failed to remove local file $file_being_moved : $!";
                    Yars::Tools->cleanup_tree(dirname($file_being_moved));
                } else {
                    my ( $message, $code ) = $tx->error;
                    ERROR "Could not put to $url : $message"
                      . ( $code ? " (code $code)" : "" );
                    if ( $tx->res && ( my $body = $tx->res->body ) ) {
                        ERROR "Error body: $body";
                    }
                }
                undef $file_being_moved;
                undef $md5_being_moved;
            });
        return;
    };

    WARN "I don't know where file with md5 [$md5_being_moved] belongs, neither local nor remote";
}

sub _balance {
    my $config = shift;
    Yars::Tools->refresh_config;
    DEBUG "Checking for stashed files (".time.")\n";
    my @disks = map @{ $_->{disks} }, $config->servers;
    my @local = grep { Yars::Tools->disk_is_local($_->{root}) } @disks;
    LOGDIE "No local disks" unless @local;
    _tidy_stashed_files($_) for @local;
}

=item init

Initialize a daemon, add it to the IOLoop.

=cut

sub init {
    my $self = shift;
    my $config = $self->app->config;
    my $max_balancers = $config->max_balancers(default => 1);
    my $balance_delay = $config->balance_delay(default => 10);
    Mojo::IOLoop->recurring( $balance_delay => sub { _balance($config) });
    WARN "Starting balancer ($$) with interval $balance_delay";
    return 1;
}

sub _new_daemon {
    my $config = Clustericious::Config->new("Yars");
    my $which = $ENV{YARS_WHICH} || '0';
    my $root = $ENV{HARNESS_ACTIVE} ? "/tmp/yars.test.$<.$which.run" : "$ENV{HOME}/var/run/yars";
    my $root_log = $ENV{HARNESS_ACTIVE} ? "/tmp/yars.test.$<.$which.log" : "$ENV{HOME}/var/log/yars";
    my $args = $config->proc_daemon(
        default => {
            pid_file     => "$root/balancer.pid",
            work_dir     => ($ENV{HARNESS_ACTIVE} ? getcwd() : "$root/balancer"),
            child_STDOUT => "$root_log/balancer.out.log",
            child_STDERR => "$root_log/balancer.err.log"
        }
    );
    -d $args->{work_dir} or do {
        INFO "making $args->{work_dir}";
        mkpath $args->{work_dir};
    };
    -d dirname($args->{child_STDERR}) or mkpath dirname($args->{child_STDERR});
    -d dirname($args->{pid_file}) or mkpath dirname($args->{pid_file});
    my %a = %$args;
    return Proc::Daemon->new( %a );
}

sub start_balancers {
    # TODO : Currently we only support one daemon.
    shift->spawn_daemon(@_);
}

sub spawn_daemon {
    my $app = shift;
    my $daemon = _new_daemon();
    my $pid = $daemon->Init;
    if (!$pid) {
        Mojo::IOLoop->singleton(Mojo::IOLoop->new());
        # child
        $Log::Log4perl::Logger::INITIALIZED = 0;
        $app = Yars->new();
        $app->init_logging();
        WARN "Balancer ($$) starting";
        Yars::Balancer->new(app => $app)->init;
        while (1) {
            Mojo::IOLoop->start;
            WARN "restarting ioloop";
            sleep 2;
        }
        exit;
    }
    INFO "Started balancer $pid";
    sleep 1;
    kill 0, $pid or WARN "Balancer $pid exited, see ".$daemon->{child_STDERR};
}

sub stop_balancers {
    my $app = shift;
    my $daemon = _new_daemon();
    $daemon->Kill_Daemon or WARN "Couldn't stop balancer (pid file ".$daemon->{pid_file}.")";
}

1;

