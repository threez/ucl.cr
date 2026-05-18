module Ucl
  # Base exception class for all UCL-related errors.
  #
  # Raised when a general UCL operation fails (e.g., null object returned,
  # key not found, type mismatch during deserialization).
  #
  # ```
  # begin
  #   obj = Ucl.parse("invalid {{{")
  # rescue ex : Ucl::Error
  #   puts ex.message
  # end
  # ```
  class Error < Exception
  end

  # Raised when the UCL parser encounters a syntax error.
  #
  # Provides `#line` and `#column` accessors indicating where in the input
  # the error occurred.
  #
  # ```
  # begin
  #   Ucl.parse("key = ;")
  # rescue ex : Ucl::ParseError
  #   puts "Parse error at #{ex.line}:#{ex.column}: #{ex.message}"
  # end
  # ```
  class ParseError < Error
    # The line number where the parse error occurred (1-based), or 0 if unknown.
    getter line : UInt32

    # The column number where the parse error occurred (1-based), or 0 if unknown.
    getter column : UInt32

    def initialize(message : String, @line : UInt32 = 0, @column : UInt32 = 0)
      super(message)
    end
  end
end
