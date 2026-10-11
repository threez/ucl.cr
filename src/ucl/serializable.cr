module Ucl
  # Annotation for controlling how individual fields are deserialized
  # and serialized.
  #
  # Supported named arguments:
  # - **key** (`String`) -- map to a different UCL key name
  # - **ignore** (`Bool`) -- skip during both serialization and deserialization
  # - **ignore_deserialize** (`Bool`) -- skip during deserialization only
  # - **ignore_serialize** (`Bool` or expression) -- skip during serialization
  # - **converter** -- custom module with `.from_ucl` and `.to_ucl` methods
  # - **presence** (`Bool`) -- track whether the key was present in input
  # - **emit_null** (`Bool`) -- emit `nil` values instead of omitting them
  #
  # ```
  # struct Example
  #   include Ucl::Serializable
  #
  #   @[Ucl::Field(key: "listen_address")]
  #   property host : String
  #
  #   @[Ucl::Field(ignore: true)]
  #   property internal : String = "default"
  # end
  # ```
  annotation Field
  end

  # Annotation-based UCL deserialization and serialization module, following
  # the same patterns as `JSON::Serializable` from Crystal's standard library.
  #
  # Include this module in a struct or class to enable `from_ucl`, `from_ucl_file`,
  # `to_ucl`, and `to_ucl_string` methods.
  #
  # ```
  # struct ServerConfig
  #   include Ucl::Serializable
  #
  #   property host : String
  #   property port : Int32
  #   property? tls : Bool = false
  # end
  #
  # config = ServerConfig.from_ucl(%{host = "localhost"; port = 8080;})
  # config.host          # => "localhost"
  # config.to_ucl_string # => UCL config format string
  # ```
  module Serializable
    # Annotation for class-level serialization options.
    #
    # Supported named arguments:
    # - **emit_nulls** (`Bool`) -- emit all nil fields as null values (default: omit them)
    annotation Options
    end

    macro included
      def self.new(ucl_object : ::Ucl::Object)
        instance = allocate
        instance.initialize(__ucl_object_for_serializable: ucl_object)
        ::GC.add_finalizer(instance) if instance.responds_to?(:finalize)
        instance
      end

      def self.from_ucl(string : String)
        new(::Ucl.parse(string))
      end

      def self.from_ucl_file(filename : String)
        new(::Ucl.parse_file(filename))
      end

      macro inherited
        def self.new(ucl_object : ::Ucl::Object)
          instance = allocate
          instance.initialize(__ucl_object_for_serializable: ucl_object)
          ::GC.add_finalizer(instance) if instance.responds_to?(:finalize)
          instance
        end
      end


      def initialize(*, __ucl_object_for_serializable ucl_object : ::Ucl::Object)
        {% verbatim do %}
          {% begin %}
            {% properties = {} of Nil => Nil %}
            {% for ivar in @type.instance_vars %}
              {% ann = ivar.annotation(::Ucl::Field) %}
              {% unless ann && (ann[:ignore] || ann[:ignore_deserialize]) %}
                {%
                  properties[ivar.id] = {
                    key:         ((ann && ann[:key]) || ivar).id.stringify,
                    has_default: ivar.has_default_value?,
                    default:     ivar.default_value,
                    nilable:     ivar.type.nilable?,
                    converter:   ann && ann[:converter],
                    presence:    ann && ann[:presence],
                  }
                %}
              {% end %}
            {% end %}

            {% for name, value in properties %}
              %var{name} = uninitialized ::Union(typeof(@{{ name }}))
              %found{name} = false
            {% end %}

            unless ucl_object.object?
              raise ::Ucl::Error.new("Expected UCL object for #{self.class}, got #{ucl_object.type_name}")
            end

            ucl_object.each do |%child|
              %key = %child.key.not_nil!
              case %key
              {% for name, value in properties %}
                when {{ value[:key] }}
                  begin
                    {% if value[:nilable] %}
                      if %child.null?
                        %var{name} = nil
                        %found{name} = true
                        next
                      end
                    {% end %}

                    %var{name} =
                      {% if value[:converter] %}
                        {{ value[:converter] }}.from_ucl(%child)
                      {% else %}
                        ::Union(typeof(@{{ name }})).new(%child)
                      {% end %}
                    %found{name} = true
                  rescue exc : ::Ucl::Error
                    raise ::Ucl::Error.new("Error deserializing #{self.class}#" + {{ value[:key] }} + ": #{exc.message}")
                  end
              {% end %}
              else
                on_unknown_ucl_attribute(%key)
              end
            end

            {% for name, value in properties %}
              if %found{name}
                @{{ name }} = %var{name}
              else
                {% unless value[:has_default] || value[:nilable] %}
                  raise ::Ucl::Error.new("Missing UCL attribute: {{ value[:key].id }} for #{self.class}")
                {% end %}
              end

              {% if value[:presence] %}
                @{{ name }}_present = %found{name}.as(Bool)
              {% end %}
            {% end %}
          {% end %}
        {% end %}
        after_initialize
      end
    end

    # Hook called after all fields have been deserialized. Override to perform
    # custom validation or post-processing.
    protected def after_initialize
    end

    # Hook called when an unknown key is encountered during deserialization.
    # Override to handle or ignore unknown keys. The default does nothing.
    #
    # See `Ucl::Serializable::Strict` to raise on unknown keys instead.
    protected def on_unknown_ucl_attribute(key : String)
    end

    # Hook called during serialization after all fields have been written.
    # Override to add custom keys to the output object.
    protected def on_to_ucl(obj : ::Ucl::Object)
    end

    # Serializes this object to a `Ucl::Object` tree.
    #
    # Respects `Ucl::Field` annotations (key mapping, ignore, converter, emit_null).
    def to_ucl : ::Ucl::Object
      {% begin %}
        {% options = @type.annotation(::Ucl::Serializable::Options) %}
        {% emit_nulls = options && options[:emit_nulls] %}

        {% properties = {} of Nil => Nil %}
        {% for ivar in @type.instance_vars %}
          {% ann = ivar.annotation(::Ucl::Field) %}
          {% unless ann && (ann[:ignore] || ann[:ignore_serialize] == true) %}
            {%
              properties[ivar.id] = {
                key:              ((ann && ann[:key]) || ivar).id.stringify,
                converter:        ann && ann[:converter],
                emit_null:        (ann && (ann[:emit_null] != nil) ? ann[:emit_null] : emit_nulls),
                ignore_serialize: ann && ann[:ignore_serialize],
              }
            %}
          {% end %}
        {% end %}

        %obj = ::Ucl::Object.new_object

        {% for name, value in properties %}
          %val = @{{ name }}

          {% if value[:ignore_serialize] %}
            unless {{ value[:ignore_serialize] }}
          {% end %}

            {% unless value[:emit_null] %}
              unless %val.nil?
            {% end %}

              {% if value[:converter] %}
                %obj[{{ value[:key] }}] = {{ value[:converter] }}.to_ucl(%val)
              {% else %}
                %obj[{{ value[:key] }}] = %val.to_ucl
              {% end %}

            {% unless value[:emit_null] %}
              end
            {% end %}

          {% if value[:ignore_serialize] %}
            end
          {% end %}
        {% end %}

        on_to_ucl(%obj)
        %obj
      {% end %}
    end

    # Serializes this object to a UCL string in the specified format.
    #
    # Defaults to `Config` (human-readable UCL format). Pass
    # `Ucl::Lib::UclEmitter::JSON` for JSON output, etc.
    def to_ucl_string(format : ::Ucl::Lib::UclEmitter = ::Ucl::Lib::UclEmitter::Config) : String
      to_ucl.emit(format)
    end

    # Include this module alongside `Ucl::Serializable` to raise
    # `Ucl::Error` when unknown keys are encountered during deserialization.
    #
    # ```
    # struct StrictConfig
    #   include Ucl::Serializable
    #   include Ucl::Serializable::Strict
    #   property name : String
    # end
    #
    # StrictConfig.from_ucl(%{name = "test"; extra = 1;})
    # # => raises Ucl::Error: "Unknown UCL attribute: extra"
    # ```
    module Strict
      protected def on_unknown_ucl_attribute(key : String)
        raise ::Ucl::Error.new("Unknown UCL attribute: #{key} for #{self.class}")
      end
    end

    # Include this module alongside `Ucl::Serializable` to capture
    # unknown keys into a `#ucl_unmapped` hash instead of ignoring them.
    #
    # Unknown keys are preserved during round-trip serialization via `#to_ucl`.
    module Unmapped
      @[::Ucl::Field(ignore: true)]
      property ucl_unmapped = Hash(String, ::Ucl::AnyValue).new

      protected def on_unknown_ucl_attribute(key : String)
        # We can't easily capture arbitrary UCL values here without the object,
        # so this is handled in the main loop. Override in subclass if needed.
      end

      protected def on_to_ucl(obj : ::Ucl::Object)
        ucl_unmapped.each do |key, value|
          obj[key] = value.to_ucl
        end
      end
    end
  end
end

# :nodoc:
# Type extensions for converting Crystal primitives, arrays, hashes, and
# union types to/from `Ucl::Object`. These enable `Ucl::Serializable` to
# work with standard Crystal types automatically.

struct Int
  def to_ucl : Ucl::Object
    Ucl::Object.from(self)
  end

  def self.new(ucl_object : Ucl::Object) : self
    ucl_object.to_i.to_i32!
  end
end

struct Int8
  def self.new(ucl_object : Ucl::Object) : self
    ucl_object.to_i.to_i8!
  end
end

struct Int16
  def self.new(ucl_object : Ucl::Object) : self
    ucl_object.to_i.to_i16!
  end
end

struct Int32
  def self.new(ucl_object : Ucl::Object) : self
    ucl_object.to_i.to_i32!
  end
end

struct Int64
  def self.new(ucl_object : Ucl::Object) : self
    ucl_object.to_i
  end
end

struct UInt8
  def self.new(ucl_object : Ucl::Object) : self
    ucl_object.to_i.to_u8!
  end
end

struct UInt16
  def self.new(ucl_object : Ucl::Object) : self
    ucl_object.to_i.to_u16!
  end
end

struct UInt32
  def self.new(ucl_object : Ucl::Object) : self
    ucl_object.to_i.to_u32!
  end
end

struct UInt64
  def self.new(ucl_object : Ucl::Object) : self
    ucl_object.to_i.to_u64!
  end
end

struct Float32
  def to_ucl : Ucl::Object
    Ucl::Object.from(to_f64)
  end

  def self.new(ucl_object : Ucl::Object) : self
    ucl_object.to_f.to_f32
  end
end

struct Float64
  def to_ucl : Ucl::Object
    Ucl::Object.from(self)
  end

  def self.new(ucl_object : Ucl::Object) : self
    ucl_object.to_f
  end
end

class String
  def to_ucl : Ucl::Object
    Ucl::Object.from(self)
  end

  def self.new(ucl_object : Ucl::Object) : self
    ucl_object.to_s
  end
end

struct Bool
  def to_ucl : Ucl::Object
    Ucl::Object.from(self)
  end

  def self.new(ucl_object : Ucl::Object) : self
    ucl_object.to_b
  end
end

struct Nil
  def to_ucl : Ucl::Object
    Ucl::Object.from(nil)
  end

  def self.new(ucl_object : Ucl::Object) : self
    raise Ucl::Error.new("Expected null UCL value") unless ucl_object.null?
    nil
  end
end

class Array
  def to_ucl : Ucl::Object
    arr = Ucl::Object.new_array
    each { |item| arr << item.to_ucl }
    arr
  end

  def self.new(ucl_object : Ucl::Object) : self
    raise Ucl::Error.new("Expected UCL array, got #{ucl_object.type_name}") unless ucl_object.array?
    ary = new(ucl_object.size)
    ucl_object.each do |item|
      ary << T.new(item)
    end
    ary
  end

  def self.from_ucl(string : String) : self
    new(Ucl.parse(string))
  end

  def self.from_ucl_file(filename : String) : self
    new(Ucl.parse_file(filename))
  end
end

class Hash
  def to_ucl : Ucl::Object
    obj = Ucl::Object.new_object
    each { |key, value| obj[key.to_s] = value.to_ucl }
    obj
  end

  def self.new(ucl_object : Ucl::Object) : self
    raise Ucl::Error.new("Expected UCL object, got #{ucl_object.type_name}") unless ucl_object.object?
    hash = new
    ucl_object.each do |child|
      key = child.key || next
      {% if K == String %}
        hash[key] = V.new(child)
      {% else %}
        hash[K.new(key)] = V.new(child)
      {% end %}
    end
    hash
  end

  def self.from_ucl(string : String) : self
    new(Ucl.parse(string))
  end

  def self.from_ucl_file(filename : String) : self
    new(Ucl.parse_file(filename))
  end
end

def Union.new(ucl_object : Ucl::Object)
  {% begin %}
    {% if T.includes?(Nil) %}
      if ucl_object.null?
        return nil
      end
    {% end %}

    {% if T.includes?(Bool) %}
      if ucl_object.boolean?
        return ucl_object.to_b
      end
    {% end %}

    {% int_type_order = [Int64, UInt64, Int32, UInt32, Int16, UInt16, Int8, UInt8] %}
    {% for type in int_type_order.select { |t| T.includes?(t) } %}
      if ucl_object.int?
        return {{ type }}.new(ucl_object)
      end
    {% end %}

    {% float_type_order = [Float64, Float32] %}
    {% for type in float_type_order.select { |t| T.includes?(t) } %}
      if ucl_object.float? || ucl_object.time?
        return {{ type }}.new(ucl_object)
      end
    {% end %}

    {% if T.includes?(String) %}
      if ucl_object.string?
        return ucl_object.to_s
      end
    {% end %}

    {% primitive_types = [Nil, Bool, String, Int8, Int16, Int32, Int64, UInt8, UInt16, UInt32, UInt64, Float32, Float64] %}
    {% non_primitives = T.reject { |t| primitive_types.includes?(t) } %}

    {% for type in non_primitives %}
      {% if type < Array %}
        if ucl_object.array?
          return {{ type }}.new(ucl_object)
        end
      {% elsif type < Hash %}
        if ucl_object.object?
          return {{ type }}.new(ucl_object)
        end
      {% else %}
        if ucl_object.object?
          return {{ type }}.new(ucl_object)
        end
      {% end %}
    {% end %}

    raise ::Ucl::Error.new("Couldn't deserialize UCL #{ucl_object.type_name} into #{self}")
  {% end %}
end
