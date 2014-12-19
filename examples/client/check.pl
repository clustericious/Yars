use Yars::Client;

my $y = Yars::Client->new;
$y->check(qw[b17f875e68ea2ff30661e2f171599490 Build.PL]) or die $y->errorstring;
print $y->tx->req->url->to_string;

