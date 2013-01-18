package ZSCII::Codec;
use 5.14.0;
use warnings;
# ABSTRACT: an encoder/decoder for ZSCII

use Carp ();

sub new {
  my ($class, $arg) = @_;

  my $guts;
  if (! defined $arg) {
    $guts = { version => 5 };
  } if (! ref $arg) {
    $guts = { version => $arg };
  } else {
    $guts = $arg;
  }

  Carp::croak("only Version 5 ZSCII is supported at present")
    unless $guts->{version} == 5;

  return bless $guts => $class;
}

my %CRAPPY_V5_ALPHABET = (
  ' '  => [ 0x20 ],
  '.'  => [ 0x05, 0x12 ],
  ','  => [ 0x05, 0x13 ],
  '!'  => [ 0x05, 0x14 ],
  "\n" => [ 0x05, 0x07 ],
  (map { chr(ord('a') + $_) => [       6 + $_ ] } (0 .. 25)),
  (map { chr(ord('A') + $_) => [ 0x04, 6 + $_ ] } (0 .. 25)),
);

sub encode {
  my ($self, $string) = @_;

  my $result = '';

  my @chars  = split //, $string;
  my @zchars = map {; Carp::croak("unknown char") if ! $CRAPPY_V5_ALPHABET{$_};
                      @{ $CRAPPY_V5_ALPHABET{ $_ } } } @chars;

  while (my @triplet = splice @zchars, 0, 3) {
    $triplet[$_] ||= 5 for (0..2);
    my $value = $triplet[0] << 10
              | $triplet[1] <<  5
              | $triplet[2];

    $value |= (0x8000) if ! @zchars;

    $result .= pack 'n', $value;
  }

  return $result;
}

sub bytestring_to_zchars {
  my ($self, $bytestring) = @_;

  Carp::croak("bytestring of packed zchars is not an even number of bytes")
    if length($bytestring) % 2;

  my $terminate;
  my @zchars;
  while ($bytestring =~ /\G(..)/g) {
    # XXX: Probably allow this to warn and `last` -- rjbs, 2013-01-18
    Carp::croak("input continues after terminating byte") if $terminate;

    my $n = unpack 'n', $1;
    $terminate = $n & 0x8000;
    my $c1 = ($n & 0b0111110000000000) >> 10;
    my $c2 = ($n & 0b0000001111100000) >>  5;
    my $c3 = ($n & 0b0000000000011111);
    push @zchars, ($c1, $c2, $c3);
  }

  return @zchars;
}

sub decode {
  my ($self, $zchars) = @_;

}

1;
