use strict;
use warnings;

use Test::More;
use Test::Differences;
use Test::BinaryData;
use ZSCII::Codec;

sub bytes {
  return join q{}, map chr hex, @_;
}

my $z = ZSCII::Codec->new(5);

my $ztext = $z->encode("Hello, world.\n");

is_binary(
  $ztext,
  bytes(qw(11 AA 46 34 16 60 72 97 45 25 C8 A7)),
  "Hello, world.",
);

my @zchars = split //, $z->unpack_zchars( $ztext );
my @want   = map chr hex,
            qw(04 0D 0A 11 11 14 05 13 00 1C 14 17 11 09 05 12 05 07);
            #      H  e  l  l  o     , __  w  o  r  l  d     .    \n

# XXX: Make a patch to eq_or_diff to let me tell it to sprintf the results.
# -- rjbs, 2013-01-18
eq_or_diff(
  \@zchars,
  \@want,
  "zchars from encoded 'Hello, World.'",
);

my $text = $z->decode($ztext);

is_binary($text, "Hello, world.\n", q{we round-tripped "Hello, world.\n"!});

done_testing;
