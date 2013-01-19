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

  my $packed_zchars = $z->encode( $unicode_text );

This method takes a string of text and encodes it to a bytestring of packed
Z-characters.

Internally, it converts the Unicode text to ZSCII, then to Z-characters, and
then packs them.  Before this processing, any native newline characters (the
value of C<\n>) are converted to C<U+000D> to match the Z-Machine's use of
character 0x00D for newline.

=cut

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

Internally, it unpacks the Z-characters, converts them to ZSCII, and then
converts those to Unicode.  Any ZSCII characters 0x00D are converted to the
value of C<\n>.

=cut

sub decode {
  my ($self, $bytestring) = @_;

  my $zchars  = $self->unpack_zchars( $bytestring );
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

=method unicode_to_zscii

  my $zscii_string = $z->unicode_to_zscii( $unicode_string );

This method converts a Unicode string to a ZSCII string, using the dialect of
ZSCII for the ZSCII::Codec's configuration.

If the Unicode input contains any characters that cannot be mapped to ZSCII, an
exception is raised.

=cut

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

=method zscii_to_unicode

  my $unicode_string = $z->zscii_to_unicode( $zscii_string );

This method converts a ZSCII string to a Unicode string, using the dialect of
ZSCII for the ZSCII::Codec's configuration.

If the ZSCII input contains any characters that cannot be mapped to Unicode, an
exception is raised.  I<In the future, it may be possible to request a Unicode
replacement character instead.>

=cut

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

=method zscii_to_zchars

  my $zchars = $z->zscii_to_zchars( $zscii_string );

Given a string of ZSCII characters, this method will return a (unpacked) string
of Z-characters.

It will raise an exception on ZSCII codepoints that cannot be represented as
Z-characters, which should not be possible with legal ZSCII.

=cut

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

    $zchars = "\x05\x06"; # The escape code for a ten-bit ZSCII character.
    my $ord = ord $zscii;

    if ($ord >= 1024) {
      Carp::croak(
        sprintf "can't encode ZSCII codepoint %#v05x in Z-characters",
          $zscii_char
      );
    }

    my $top = ($ord & 0b1111100000) >> 5;
    my $bot = ($ord & 0b0000011111);

    $zchars .= chr($top) . chr($bot);
  }

  return $zchars;
}

=method zchars_to_zscii

  my $zscii = $z->zchars_to_zscii( $zchars_string );

Given a string of (unpacked) Z-characters, this method will return a string of
ZSCII characters.

It will raise an exception when the right thing to do can't be determined.
Right now, that could mean lots of things.

=cut

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
      my $next_two = substr $zchars, 0, 2, '';
      Carp::croak("ten-bit ZSCII encoding segment terminated early")
        unless length $next_two == 2;

      Carp::croak("ten-bit ZSCII encoding not yet supported"); # TODO
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

=method pack_zchars

  my $packed_zchars = $z->pack_zchars( $zchars_string );

This method takes a string of unpacked Z-characters and packs them into a
bytestring with three Z-characters per word.  The final word will have its top
bit set.

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

=method unpack_zchars

  my $zchars_string = $z->pack_zchars( $packed_zchars );

Given a bytestring of packed Z-characters, this method will unpack them into a
string of unpacked Z-characters that aren't packed anymore because they're
unpacked instead of packed.

Exceptions are raised if the input bytestring isn't made of an even number of
octets, or if the string continues past the first word with its top bit set.

=cut

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

1;