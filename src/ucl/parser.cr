module Ucl
  # Wraps a libucl parser instance for parsing UCL strings and files.
  #
  # The parser accumulates input from one or more `#add_string` or `#add_file`
  # calls, then produces a `Ucl::Object` tree via `#parse!`.
  #
  # For most use cases, prefer the convenience methods `Ucl.parse` and
  # `Ucl.parse_file` instead of using `Parser` directly.
  #
  # ```
  # parser = Ucl::Parser.new
  # parser.add_string(%{host = "localhost";})
  # parser.add_string(%{port = 8080;})
  # obj = parser.parse!
  # obj["host"].to_s # => "localhost"
  # ```
  class Parser
    @ptr : Lib::UclParser*

    # Creates a new parser with the given flags.
    #
    # Raises `Ucl::Error` if the parser cannot be allocated.
    def initialize(flags : Lib::UclParserFlags = Lib::UclParserFlags::Default)
      @ptr = Lib.ucl_parser_new(flags.to_i)
      raise Error.new("Failed to allocate UCL parser") if @ptr.null?
    end

    def finalize
      Lib.ucl_parser_free(@ptr)
    end

    # Feeds a UCL string into the parser.
    #
    # Multiple strings can be added before calling `#parse!`; they are
    # concatenated logically. Returns `self` for method chaining.
    #
    # Raises `Ucl::ParseError` if the string contains invalid UCL syntax.
    def add_string(data : String) : self
      result = Lib.ucl_parser_add_string(@ptr, data.to_unsafe, data.bytesize)
      check_error! unless result
      self
    end

    # Reads and parses a UCL file.
    #
    # Supports `.include` directives and variable expansion relative to
    # the file's directory. Returns `self` for method chaining.
    #
    # Raises `Ucl::ParseError` if the file cannot be read or contains
    # invalid UCL syntax.
    def add_file(filename : String) : self
      result = Lib.ucl_parser_add_file(@ptr, filename.to_unsafe)
      check_error! unless result
      self
    end

    # Finalizes parsing and returns the top-level `Ucl::Object`.
    #
    # The returned object is owned by the caller and will be freed
    # when garbage collected. This method should be called after all
    # input has been added via `#add_string` or `#add_file`.
    #
    # Raises `Ucl::ParseError` if the accumulated input is incomplete
    # or invalid, or `Ucl::Error` if the parser returns a null object.
    def parse! : Object
      ptr = Lib.ucl_parser_get_object(@ptr)
      if ptr.null?
        check_error!
        raise Error.new("Parser returned null object")
      end
      Object.new(ptr, owned: true)
    end

    # Registers a variable for `$VAR` substitution during parsing.
    #
    # ```
    # parser = Ucl::Parser.new
    # parser.register_variable("HOST", "localhost")
    # parser.add_string(%{host = "$HOST";})
    # parser.parse!["host"].to_s # => "localhost"
    # ```
    def register_variable(name : String, value : String) : self
      Lib.ucl_parser_register_variable(@ptr, name.to_unsafe, value.to_unsafe)
      self
    end

    # Sets standard file variables (`$FILENAME`, `$CURDIR`) based on
    # the given filename.
    #
    # When *need_expand* is `true` (the default), the path is resolved
    # to an absolute path before setting the variables.
    def set_filevars(filename : String, need_expand : Bool = true) : self
      Lib.ucl_parser_set_filevars(@ptr, filename.to_unsafe, need_expand)
      self
    end

    # Sets the default priority for objects parsed by this parser.
    #
    # Priority affects how objects are merged when multiple definitions
    # of the same key exist (higher priority wins).
    def default_priority=(priority : UInt32) : self
      Lib.ucl_parser_set_default_priority(@ptr, priority)
      self
    end

    private def check_error!
      err = Lib.ucl_parser_get_error(@ptr)
      if err && !err.null?
        message = String.new(err)
        line = Lib.ucl_parser_get_linenum(@ptr)
        column = Lib.ucl_parser_get_column(@ptr)
        raise ParseError.new(message, line.to_u32, column.to_u32)
      end
      raise Error.new("Unknown parser error")
    end
  end
end
