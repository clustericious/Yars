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

balancer_file (/tmp/yars_balancers) : A file used by the
balancers when starting/exiting in order to keep the maximum
number <= max_balancers.

=head1 TODO

Maybe use inotify instead of periodically checking
with File::Find.

=over

=cut

package Yars::Balancer;
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

has 'app';
has 'balancer_file'; # stores the list of balancers

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
                    return if /\/is_down$/;
                    my $dir = $File::Find::dir;
                    $dir =~ s/$disk->{root}//;
                    $dir =~ s[/][]g;
                    my $md5 = $dir;
                    if (grep { $dir =~ /^$_/i } @belong) {
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
        $UA->put( $url =>
             { 'X-Yars-NoStash' => 1 } =>
             Mojo::Asset::File->new( path => $file_being_moved )->slurp =>
              sub {
                my ( $self, $tx ) = @_;
                if ( my $res = $tx->success ) {
                    TRACE "Successfully put $name to $destination_server";
                    unlink $file_being_moved or
                        WARN "Failed to remove local file $file_being_moved : $!";
                    Yars::Tools->cleanup_tree(dirname($file_being_moved));
                    undef $file_being_moved;
                    undef $md5_being_moved;
                }
                else {
                    my ( $message, $code ) = $tx->error;
                    ERROR "Could not put to $url : $message"
                      . ( $code ? " (code $code)" : "" );
                    if ( $tx->res && ( my $body = $tx->res->body ) ) {
                        ERROR "Error body: $body";
                    }
                }
            }
        );
        return;
    }

    WARN "I don't know where file with md5 [$md5_being_moved] belongs, neither local nor remote";
}

sub _balance {
    my $config = shift;
    DEBUG "Checking for stashed files (".time.")\n";
    my @disks = map @{ $_->{disks} }, $config->servers;
    _tidy_stashed_files($_) for grep { Yars::Tools->disk_is_local($_->{root}) } @disks;
}

=item init_and_start

Initialize and start the balancer.

=cut

our $IAmABalancer = 0;
sub init_and_start {
    my $self = shift;
    my $config = $self->app->config;
    my $max_balancers = $config->max_balancers(default => 1);
    my $test = $ENV{HARNESS_ACTIVE} ? ".test" : "";
    $self->balancer_file($config->balancer_file(default => "/tmp/yars_balancers$test"));
    $self->maybe_start or do {
        Mojo::IOLoop->recurring((60*60*24 + int rand 6000) => sub {
            # Stagger delay to avoid race conditions
            $self->maybe_start;
        });

        return $self;
    };
    return $self;
}

=item maybe_start

Start this balancer only if it is not running and the
number of running balancers is <= the max balancer setting.

=cut

sub maybe_start {
    my $self = shift;
    my $config = $self->app->config;
    my $max_balancers = $config->max_balancers(default => 1);
    $self->_add_pid_to_balancers($max_balancers) or return 0;
    return 0 if $IAmABalancer;
    DEBUG "Starting balancer ($$)";
    $IAmABalancer = 1;
    my $balance_delay = $config->balance_delay(default => 10);
    my $ioloop = Mojo::IOLoop->singleton;
    $ioloop->recurring($balance_delay => sub {  _balance($config) });
    return 1;
}

sub DESTROY {
    my $self = shift;
    # remove self from balancer file
    $self->_remove_pid_from_balancers if $IAmABalancer;
    $IAmABalancer = 0;
    $self->SUPER::DESTROY if $self->can("SUPER::DESTROY");
}

sub _sanity_check_balancer_file {
    my $pids = shift;
    for ( keys %$pids ) {
        kill 0, $_ or do {
            WARN "balancer $_ is not running, removing from list.";
            delete $pids->{$_};
          }
    }
}

sub _add_pid_to_balancers {
    my $self = shift;
    my ($max_balancers) = @_;
    my $filename = $self->balancer_file;
    my $j = Mojo::JSON->new();
    # see perldoc -q lock
    sysopen my $fh, $filename, O_RDWR|O_CREAT or LOGDIE "can't open $filename: $!";
    flock $fh, LOCK_EX                        or LOGDIE "can't flock $filename: $!";
    my $content = join '', <$fh>;
    my $pids = {};
    $pids = $j->decode($content) if $content;
    _sanity_check_balancer_file($pids);
    if ( (keys %$pids) >= $max_balancers) {
        TRACE "Balancer count is ".(keys %$pids)." not starting a new one.";
        close $fh or LOGDIE "can't close $filename: $!";
        return 0;
    }
    $pids->{$$} = time;
    my $out = $j->encode($pids);
    seek $fh, 0, 0    or LOGDIE "can't rewind $filename: $!";
    truncate $fh, 0   or LOGDIE "can't truncate $filename: $!";
    (print $fh $out)  or LOGDIE "can't write $filename: $!";
    close $fh         or LOGDIE "can't close $filename: $!";
    return 1;
}

sub _remove_pid_from_balancers {
    my $self = shift;
    my $filename = $self->balancer_file;
    my $j = Mojo::JSON->new();
    # see perldoc -q lock
    sysopen my $fh, $filename, O_RDWR or do { WARN "can't open $filename: $!"; return 0; };
    flock $fh, LOCK_EX                or do { WARN "can't flock $filename: $!"; return 0; };
    my $content = do { local $\; <$fh>; };
    my $pids = {};
    $pids = $j->decode($content) if $content;
    _sanity_check_balancer_file($pids);
    delete $pids->{$$}             or WARN "PID $$ was not in balancer file";
    seek $fh, 0, 0                 or do { WARN "can't rewind $filename: $!";   return 0; };
    truncate $fh, 0                or do { WARN "can't truncate $filename: $!"; return 0; };
    (print $fh $j->encode($pids))  or do { WARN "can't write $filename: $!";    return 0; };
    close $fh                      or do { WARN "can't close $filename: $!";    return 0; };
    return 1;
}

1;


