package ZSCII::Codec;
use 5.14.0;
use warnings;
# ABSTRACT: an encoder/decoder for ZSCII

use Carp ();
use charnames ();

=head1 OVERVIEW

ZSCII::Codec is a class for objects that are encoders/decoders of Z-Machine
text.  Right now, ZSCII::Codec only implements Version 5, and even that
partially.  Only the basic three alphabets are supported for encoding and
decoding.  Three character sequences (i.e., full ten bit ZSCII characters) are
not yet supported.  Alternate alphabet tables are not yet supported.

In the future, these will be supported, and it will be possible to map
characters not found in Unicode.  For example, the ZSCII "sentence space" could
be mapped to the Unicode "EM SPACE" character.

At present, a text string can be encoded to a packed Z-character string, but
not to an array of ZSCII values.

=cut

=method new

  my $z = ZSCII::Codec->new;
  my $z = ZSCII::Codec->new(\%arg);
  my $z = ZSCII::Codec->new($version);

This returns a new codec.  The only valid argument is C<version>, which gives
the version of Z-machine to target.  The default is 5.  If the only argument is
a number, it will be used as the version to target.

=cut

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

=method encode

  my $packed_zchars = $z->encode( $text );

This method takes a string of text and encodes it to a bytestring of packed
Z-characters.

=cut

# Unicode text
# |        ^
# v        |
# ZSCII text
# |        ^
# v        |
# Z-characters
# |        ^
# v        |
# packed Z-characters

sub encode {
  my ($self, $string) = @_;

  $string =~ s/\n/\x0D/g;

  my $zscii  = $self->unicode_to_zscii($string);
  my $zchars = $self->zscii_to_zchars($zscii);

  return $self->pack_zchars($zchars);
}

=method decode

  my $text = $z->decode( $packed_zchars );

This method takes a bytestring of packed Z-characters and returns a string of
text.

=cut

sub decode {
  my ($self, $bytestring) = @_;

  my $zchars  = $self->unpack_zchars( $bytestring);
  my $zscii   = $self->zchars_to_zscii( $zchars );
  my $unicode = $self->zscii_to_unicode( $zscii );

  $unicode =~ s/\x0D/\n/g;

  return $unicode;
}

my %ZSCII_FOR = (
  "\N{NULL}"   => chr 0x00,
  "\N{DELETE}" => chr 0x08,
  "\x0D"       => chr 0x0D,
  "\N{ESCAPE}" => chr 0x1B,

  (map {; chr $_ => chr $_ } (0x20 .. 0x7E)), # ASCII maps over

  # 0x09B - 0x0FB are the "extra characters" and need alphabet table code
  # 0x0FF - 0x3FF are undefined and never (?) used
);

my %UNICODE_FOR = reverse %ZSCII_FOR;

sub unicode_to_zscii {
  my ($self, $unicode_text) = @_;

  my $zscii = '';
  for (0 .. length($unicode_text) - 1) {
    my $char = substr $unicode_text, $_, 1;

    Carp::croak(
      sprintf "no ZSCII character available for Unicode U+%v05X <%s>",
        $char,
        charnames::viacode(ord $char),
    ) unless my $zscii_char = $ZSCII_FOR{ $char };

    $zscii .= $zscii_char;
  }

  return $zscii;
}

# We can use these characters below because they all (save for the magic A2-C6)
# are the same in Unicode/ASCII/ZSCII. -- rjbs, 2013-01-18
my @ALPHABETS = (
  [ 'a' .. 'z' ],
  [ 'A' .. 'Z' ],
  [ \0,     # special: read 2 chars for 10-bit zscii character
    "\x0D",
    (0 .. 9),
    do { no warnings 'qw'; qw[ . , ! ? _ # ' " / \ - : ( ) ] },
  ],
);

my %DEFAULT_SHORTCUT = (q{ } => chr(0));
for my $i (0 .. 2) {
  for my $j (0 .. $#{ $ALPHABETS[$i] }) {
    next if $i == 2 and $j == 0; # that guy is magic! -- rjbs, 2013-01-18
    $DEFAULT_SHORTCUT{ $ALPHABETS[$i][$j] }
      = $i ? chr(0x03 + $i) . chr($j + 6) : chr($j + 6);
  }
}

sub zscii_to_zchars {
  my ($self, $zscii) = @_;

  return '' unless length $zscii;

  my $zchars = '';
  for (0 .. length($zscii) - 1) {
    my $zscii_char = substr($zscii, $_, 1);
    if ($DEFAULT_SHORTCUT{ $zscii_char }) {
      $zchars .= $DEFAULT_SHORTCUT{ $zscii_char };
      next;
    }

    Carp::croak(
      sprintf "can't encode ZSCII codepoint %#v05x in Z-characters",
        $zscii_char
    );
  }

  return $zchars;
}

=method pack_zchars

  my $packed_zchars = $z->pack_zchars( $zchars_string );

=cut

sub pack_zchars {
  my ($self, $zchars) = @_;

  my $bytestring = '';

  while (my $substr = substr $zchars, 0, 3, '') {
    $substr .= chr(5) until length $substr == 3;

    my $value = ord(substr($substr, 0, 1)) << 10
              | ord(substr($substr, 1, 1)) <<  5
              | ord(substr($substr, 2, 1));

    $value |= (0x8000) if ! length $zchars;

    $bytestring .= pack 'n', $value;
  }

  return $bytestring;
}

sub unpack_zchars {
  my ($self, $bytestring) = @_;

  Carp::croak("bytestring of packed zchars is not an even number of bytes")
    if length($bytestring) % 2;

  my $terminate;
  my $zchars = '';
  while (my $word = substr $bytestring, 0, 2, '') {
    # XXX: Probably allow this to warn and `last` -- rjbs, 2013-01-18
    Carp::croak("input continues after terminating byte") if $terminate;

    my $n = unpack 'n', $word;
    $terminate = $n & 0x8000;

    my $c1 = chr( ($n & 0b0111110000000000) >> 10 );
    my $c2 = chr( ($n & 0b0000001111100000) >>  5 );
    my $c3 = chr( ($n & 0b0000000000011111)       );

    $zchars .= "$c1$c2$c3";
  }

  return $zchars;
}

sub zchars_to_zscii {
  my ($self, $zchars) = @_;

  my $text = '';
  my $alphabet = 0;

  # We copy to avoid destroying our input.  That's just good manners.
  # -- rjbs, 2013-01-18
  while (length $zchars) {
    my $char = substr $zchars, 0, 1, '';

    last unless defined $char; # needed because of redo below

    my $ord = ord $char;

    if ($ord eq 0) { $text .= q{ }; next; }

    if    ($ord == 0x04) { $alphabet = 1; redo }
    elsif ($ord == 0x05) { $alphabet = 2; redo }

    if ($alphabet == 2 && $ord == 0x06) {
      Carp::croak("ten-bit ZSCII characters not yet implemented");
    }

    if ($ord >= 0x06 && $ord <= 0x1F) {
      $text .= $ALPHABETS[ $alphabet ][ $ord - 6 ];
      $alphabet = 0;
      next;
    }

    Carp::croak("unknown zchar <$char> encountered in alphabet <$alphabet>");
  }

  return $text;
}

sub zscii_to_unicode {
  my ($self, $zscii) = @_;

  my $unicode = '';
  for (0 .. length($zscii) - 1) {
    my $char = substr $zscii, $_, 1;

    Carp::croak(
      sprintf "no Unicode character available for ZSCII %#v05x", $char,
    ) unless my $unicode_char = $UNICODE_FOR{ $char };

    $unicode .= $unicode_char;
  }

  return $unicode;
}

1;
