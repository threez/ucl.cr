require "./ucl/lib"
require "./ucl/error"
require "./ucl/parser"
require "./ucl/object"
require "./ucl/serializable"

# Crystal bindings to [libucl](https://github.com/vstakhov/libucl), the
# Universal Configuration Language library.
#
# UCL is a human-friendly configuration format that is a superset of JSON
# with nginx-like syntax, used extensively in FreeBSD (pkg, jail.conf, etc.).
#
# There are two main ways to use this library:
#
# - **Untyped** access via `Ucl::Object` -- parse and navigate the UCL tree directly.
# - **Typed** deserialization via `Ucl::Serializable` -- map UCL to Crystal structs/classes,
#   following the same patterns as `JSON::Serializable`.
#
# ### Quick start
#
# ```
# require "ucl"
#
# # Untyped
# obj = Ucl.parse(%{server { host = "localhost"; port = 8080; }})
# obj["server"]["host"].to_s # => "localhost"
#
# # Typed
# struct ServerConfig
#   include Ucl::Serializable
#   property host : String
#   property port : Int32
# end
#
# config = ServerConfig.from_ucl(%{host = "localhost"; port = 8080;})
# config.host # => "localhost"
# ```
module Ucl
  VERSION = "0.1.2"

  # Recursive type alias for deep conversion of UCL trees to native Crystal types.
  # Returned by `Ucl::Object#to_any`.
  alias AnyValue = (Bool | Int64 | Float64 | String | Array(AnyValue) | Hash(String, AnyValue))?

  # Parses a UCL string and returns the top-level object.
  #
  # ```
  # obj = Ucl.parse(%{key = "value";})
  # obj["key"].to_s # => "value"
  # ```
  #
  # Raises `Ucl::ParseError` if the input is not valid UCL.
  def self.parse(string : String, flags : Lib::UclParserFlags = Lib::UclParserFlags::Default) : Object
    parser = Parser.new(flags)
    parser.add_string(string)
    parser.parse!
  end

  # Parses a UCL file and returns the top-level object.
  #
  # ```
  # obj = Ucl.parse_file("/etc/pkg/FreeBSD.conf")
  # ```
  #
  # Raises `Ucl::ParseError` if the file cannot be read or contains invalid UCL.
  def self.parse_file(filename : String, flags : Lib::UclParserFlags = Lib::UclParserFlags::Default) : Object
    parser = Parser.new(flags)
    parser.add_file(filename)
    parser.parse!
  end
end
