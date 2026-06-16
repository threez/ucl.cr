# ucl.cr

Crystal bindings to [libucl](https://github.com/vstakhov/libucl), the Universal Configuration Language library. UCL is a human-friendly configuration format that is a superset of JSON with nginx-like syntax, used extensively in FreeBSD (pkg, jail.conf, etc.).

## Installation

Install the native `libucl` library for your platform:

- **FreeBSD** — ships in base; no extra packages needed
- **Linux** — build from source (see below); distro packages are too old
- **macOS (Homebrew)** — `brew install libucl`

Linux distro packages (`libucl-dev`, `ucl-devel`) ship an older version of libucl that is missing the safe iterator API. Build from source instead:

```sh
sudo apt-get install cmake   # or dnf install cmake
git clone --depth 1 https://github.com/vstakhov/libucl.git
cmake -S libucl -B libucl/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
sudo cmake --build libucl/build --target install
```

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  ucl:
    github: threez/ucl.cr
```

Then run `shards install`.

## Usage

There are two main ways to use this library: **untyped** access via `Ucl::Object`, and **typed** deserialization via `Ucl::Serializable`.

### Untyped: `Ucl::Object`

Parse UCL and navigate the result tree directly. Best for exploratory access, simple scripts, or dynamic configs where the schema isn't fixed.

#### Parsing

```crystal
require "ucl"

# Parse a string
obj = Ucl.parse(%{
  server {
    host = "0.0.0.0";
    port = 8080;
    tls = true;
  }
  allowed_ips = ["10.0.0.1", "10.0.0.2"];
})

# Parse a file
obj = Ucl.parse_file("/etc/pkg/FreeBSD.conf")
```

#### Accessing values

```crystal
# Key lookup
obj["server"]["host"].to_s  # => "0.0.0.0"
obj["server"]["port"].to_i  # => 8080
obj["server"]["tls"].to_b   # => true

# Safe access (returns nil instead of raising)
obj["missing"]?             # => nil
obj["server"]["port"].to_i? # => 8080
obj["server"]["port"].to_s? # => nil (type mismatch)

# Dot-notation path lookup
obj.at("server.host").to_s  # => "0.0.0.0"
obj.at?("server.missing")   # => nil

# Array access
obj["allowed_ips"][0].to_s  # => "10.0.0.1"
obj["allowed_ips"].size     # => 2
```

#### Type checking

```crystal
obj["server"].object?        # => true
obj["allowed_ips"].array?    # => true
obj["server"]["port"].int?   # => true
obj["server"]["host"].string? # => true
obj["server"]["tls"].boolean? # => true
```

#### Iteration

`Ucl::Object` includes `Enumerable`. Iterating over an object yields its key-value entries; iterating over an array yields its elements.

```crystal
# Iterate object keys
obj["server"].each do |entry|
  puts "#{entry.key} = #{entry.to_s_forced}"
end

# Use Enumerable methods
keys = obj["server"].map { |e| e.key }
```

#### Emission

Serialize back to different output formats:

```crystal
obj.to_json          # => formatted JSON
obj.to_compact_json  # => compact JSON
obj.to_config        # => UCL config format
obj.to_yaml_string   # => YAML
```

#### Building objects programmatically

```crystal
obj = Ucl::Object.new_object
obj["name"] = "myapp"
obj["port"] = 8080
obj["debug"] = false

arr = Ucl::Object.new_array
arr << "one"
arr << "two"
obj["tags"] = arr

puts obj.to_config
```

#### Deep conversion

Convert the entire tree to native Crystal types (`Hash`, `Array`, `Int64`, `Float64`, `Bool`, `String`, `Nil`):

```crystal
native = obj.to_any
# => {"server" => {"host" => "0.0.0.0", "port" => 8080, ...}, ...}
```

### Typed: `Ucl::Serializable`

Map UCL structures to Crystal structs and classes with compile-time type safety. Follows the same patterns as `JSON::Serializable` from Crystal's standard library.

#### Basic usage

```crystal
require "ucl"

struct ServerConfig
  include Ucl::Serializable

  property host : String
  property port : Int32
  property? tls : Bool = false
end

config = ServerConfig.from_ucl(%{
  host = "0.0.0.0";
  port = 443;
  tls = true;
})

config.host  # => "0.0.0.0"
config.port  # => 443
config.tls?  # => true
```

#### Nested structures

```crystal
struct DatabaseConfig
  include Ucl::Serializable

  property connection_string : String
  property pool_size : Int32 = 5
end

struct AppConfig
  include Ucl::Serializable

  property name : String
  property server : ServerConfig
  property database : DatabaseConfig
  property tags : Array(String) = [] of String
  property metadata : Hash(String, String) = {} of String => String
end

app = AppConfig.from_ucl(%{
  name = "myapp";
  server {
    host = "0.0.0.0";
    port = 443;
    tls = true;
  }
  database {
    connection_string = "postgres://localhost/mydb";
    pool_size = 20;
  }
  tags = ["web", "api"];
  metadata {
    env = "production";
    region = "us-east";
  }
})

app.server.host         # => "0.0.0.0"
app.database.pool_size  # => 20
app.tags                # => ["web", "api"]
app.metadata["region"]  # => "us-east"
```

#### Loading from files

```crystal
config = AppConfig.from_ucl_file("/etc/myapp.conf")
```

#### Deserializing collections directly

`Hash` and `Array` also support `from_ucl` and `from_ucl_file`. This is useful when the top-level UCL structure is a mapping of dynamic keys to typed values, like FreeBSD's pkg repository config:

```crystal
struct Repository
  include Ucl::Serializable

  property url : String
  property mirror_type : String
  property signature_type : String
  property fingerprints : String

  @[Ucl::Field(key: "enabled")]
  property? enabled : Bool = true
end

# /etc/pkg/FreeBSD.conf maps repo names to repo configs:
#   FreeBSD: { url: "...", mirror_type: "srv", ... }
#   FreeBSD-kmods: { url: "...", mirror_type: "srv", ... }

repos = Hash(String, Repository).from_ucl_file("/etc/pkg/FreeBSD.conf")

repos.each do |name, repo|
  puts "#{name}: #{repo.url} (enabled: #{repo.enabled?})"
end
```

#### `Ucl::Field` annotation

Control how individual fields are deserialized:

```crystal
struct Example
  include Ucl::Serializable

  # Map to a different UCL key
  @[Ucl::Field(key: "listen_address")]
  property host : String

  # Skip during serialization and deserialization
  @[Ucl::Field(ignore: true)]
  property internal : String = "default"

  # Skip only during serialization
  @[Ucl::Field(ignore_serialize: true)]
  property secret : String

  # Emit null values (by default nil fields are omitted)
  @[Ucl::Field(emit_null: true)]
  property optional : String?

  # Custom converter
  @[Ucl::Field(converter: MyConverter)]
  property timestamp : Time
end
```

#### Serialization

Serialize back to UCL objects or strings:

```crystal
config = ServerConfig.from_ucl(%{host = "localhost"; port = 8080;})

# To a Ucl::Object
obj = config.to_ucl
obj["host"].to_s  # => "localhost"

# To a formatted string
config.to_ucl_string                            # => UCL config format
config.to_ucl_string(Ucl::Lib::UclEmitter::JSON) # => JSON format
```

#### Strict mode

Raise on unknown keys:

```crystal
struct StrictConfig
  include Ucl::Serializable
  include Ucl::Serializable::Strict

  property name : String
end

# Raises Ucl::Error: "Unknown UCL attribute: extra"
StrictConfig.from_ucl(%{name = "test"; extra = 1;})
```

#### Supported types

- **Primitives**: `String`, `Bool`, `Int8` through `Int64`, `UInt8` through `UInt64`, `Float32`, `Float64`
- **Nilable types**: `String?`, `Int32?`, etc. -- missing keys default to `nil`
- **Default values**: `property port : Int32 = 8080`
- **Collections**: `Array(T)`, `Hash(String, V)`
- **Nested serializable types**: any struct/class that includes `Ucl::Serializable`
- **Union types**: `Int32 | String` -- dispatched by UCL value type

## About UCL

UCL (Universal Configuration Language) supports:

- JSON syntax: `{"key": "value"}`
- Nginx-like blocks: `section { key = value; }`
- Simple assignments: `key = value;` or `key: value;`
- Comments: `#` and `//` line comments, `/* */` block comments
- Includes: `.include "other.conf"`
- Variables: `$VAR` substitution
- Human-friendly sizes: `10k`, `1mb`, `2gb`
- Time values: `10s`, `5min`, `1h`
- Multiline strings: `<<EOD ... EOD`

See the [libucl documentation](https://github.com/vstakhov/libucl) for the full format specification.

## Examples

The `examples/` directory contains a complete example that parses a FreeBSD pkg repository config using both untyped and typed approaches:

```
shards build fbsd-pkg
./bin/fbsd-pkg
```

## Development

```
make          # run everything: fmt, lint, docs, spec, examples
make fmt      # format code
make lint     # run ameba linter
make spec     # run tests
make examples # build and run examples
make docs     # generate API docs
```

## Contributing

1. Fork it (<https://github.com/threez/ucl.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Vincent Landgraf](https://github.com/threez) - creator and maintainer
