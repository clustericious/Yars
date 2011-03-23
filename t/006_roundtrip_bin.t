#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Mojo;
use Mojo::ByteStream qw/b/;
use FindBin qw/$Bin/;
use Yars;

my $t = Test::Mojo->new(app => 'Yars');

local $/ = undef;
my $content = <DATA>;
my $digest = b($content)->md5_sum->to_string;

$t->put_ok("/file/my_bin_file", {}, $content)->status_is(201);
$t->get_ok("/file/my_bin_file/$digest")->status_is(200);
$t->delete_ok("/file/my_bin_file/$digest")->status_is(200);
    


done_testing();


__DATA__

ÿØÿà JFIF  H H  ÿþ AppleMark
ÿâ(ICC_PROFILE   appl   scnrRGB XYZ Ó        acspAPPL    appl                  öÖ     Ó-appl                                               rXYZ     gXYZ     bXYZ  0   wtpt  D   chad  X   ,rTRC     gTRC     bTRC     desc     =cprt  Ô   Adscm  Ô  þXYZ       tK  >  ËXYZ       Zs  ¬¦  &XYZ       (  W  ¸3XYZ       óR    Ïsf32     B  Þÿÿó&    ýÿÿû¢ÿÿý£  Ü  Àlcurv       3  desc       Camera RGB Profile           Camera RGB Profile    mluc          enUS   $  esES   ,  LdaDK   4  ÚdeDE   ,  fiFI   (   ÄfrFU   <  ÂitIT   ,  rnlNL   $  noNO      xptBR   (  JsvSE   *   ìjaJP     koKR     2zhTW     2zhCN     Ä K a m e r a n   R G B - p r o f i i l i R G B - p r o f i l   f ö r   K a m e r a0«0á0é   R G B  0×0í0Õ0¡0¤0ëexOMvøj_   R G B  r_icÏð P e r f i l   R G B   p a r a   C á m a r a R G B - k a m e r a p r o f i l R G B - P r o f i l   f ü r   K a m e r a svøg:   R G B  cÏðeNö R G B - b e s k r i v e l s e   t i l   K a m e r a R G B - p r o f i e l   C a m e r aÎtºT·|   R G B  Õ¸\ÓÇ| P e r f i l   R G B   d e   C â m e r a P r o f i l o   R G B   F o t o c a m e r a C a m e r a   R G B   P r o f i l e P r o f i l   R V B   d e   l  a p p a r e i l - p h o t o  text    Copyright 2003 Apple Computer Inc., all rights reserved.    ÿÛ C 		
