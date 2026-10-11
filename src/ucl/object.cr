module Ucl
  # Wraps a libucl object (`ucl_object_t`), providing a Crystal-friendly
  # interface for inspecting, navigating, and mutating UCL data trees.
  #
  # Objects are reference-counted. Objects returned from `Ucl.parse` or
  # constructed via `Object.new_object` / `Object.new_array` are *owned*
  # and automatically freed. Objects obtained by key/index lookup or
  # iteration are *borrowed* and remain valid as long as their parent is alive.
  #
  # Includes `Enumerable(Object)` -- iterating over an object yields its
  # key-value entries; iterating over an array yields its elements.
  #
  # ```
  # obj = Ucl.parse(%{name = "app"; port = 8080; debug = false;})
  # obj["name"].to_s  # => "app"
  # obj["port"].to_i  # => 8080
  # obj["debug"].to_b # => false
  # ```
  class Object
    include Enumerable(Object)

    @ptr : Lib::UclObjectT*
    @owned : Bool

    protected def initialize(@ptr : Lib::UclObjectT*, @owned : Bool = false)
    end

    # :nodoc:
    def finalize
      Lib.ucl_object_unref(@ptr) if @owned
    end

    # Returns the UCL type enum value of this object.
    def type : Lib::UclType
      Lib.ucl_object_type(@ptr)
    end

    # Returns the human-readable type name (e.g. `"object"`, `"string"`, `"integer"`).
    def type_name : String
      ptr = Lib.ucl_object_type_to_string(type)
      ptr.null? ? "unknown" : String.new(ptr)
    end

    # Returns `true` if this is a UCL object (key-value mapping).
    def object? : Bool
      type == Lib::UclType::Object
    end

    # Returns `true` if this is a UCL array.
    def array? : Bool
      type == Lib::UclType::Array
    end

    # Returns `true` if this is an integer value.
    def int? : Bool
      type == Lib::UclType::Int
    end

    # Returns `true` if this is a floating-point value.
    def float? : Bool
      type == Lib::UclType::Float
    end

    # Returns `true` if this is a string value.
    def string? : Bool
      type == Lib::UclType::String
    end

    # Returns `true` if this is a boolean value.
    def boolean? : Bool
      type == Lib::UclType::Boolean
    end

    # Returns `true` if this is a null value.
    def null? : Bool
      type == Lib::UclType::Null
    end

    # Returns `true` if this is a time/duration value (e.g. `10s`, `5min`).
    def time? : Bool
      type == Lib::UclType::Time
    end

    # Extracts the integer value. Returns `0` if the object is not an integer.
    #
    # For safe extraction that returns `nil` on type mismatch, use `#to_i?`.
    def to_i : Int64
      Lib.ucl_object_toint(@ptr)
    end

    # Extracts the floating-point value. Returns `0.0` if the object is not a number.
    #
    # For safe extraction that returns `nil` on type mismatch, use `#to_f?`.
    def to_f : Float64
      Lib.ucl_object_todouble(@ptr)
    end

    # Extracts the boolean value. Returns `false` if the object is not a boolean.
    #
    # For safe extraction that returns `nil` on type mismatch, use `#to_b?`.
    def to_b : Bool
      Lib.ucl_object_toboolean(@ptr)
    end

    # Extracts the string value. Returns `""` if the object is not a string.
    #
    # For safe extraction that returns `nil` on type mismatch, use `#to_s?`.
    def to_s : String
      ptr = Lib.ucl_object_tostring(@ptr)
      ptr.null? ? "" : String.new(ptr)
    end

    # :nodoc:
    def to_s(io : IO) : Nil
      io << to_s
    end

    # Converts any UCL value to its string representation, regardless of type.
    #
    # Unlike `#to_s`, this works on all types: integers become `"123"`,
    # booleans become `"true"`/`"false"`, etc.
    def to_s_forced : String
      ptr = Lib.ucl_object_tostring_forced(@ptr)
      ptr.null? ? "" : String.new(ptr)
    end

    # Safely extracts the integer value, returning `nil` if this is not an integer.
    def to_i? : Int64?
      target = uninitialized Int64
      Lib.ucl_object_toint_safe(@ptr, pointerof(target)) ? target : nil
    end

    # Safely extracts the floating-point value, returning `nil` if this is not a number.
    def to_f? : Float64?
      target = uninitialized Float64
      Lib.ucl_object_todouble_safe(@ptr, pointerof(target)) ? target : nil
    end

    # Safely extracts the boolean value, returning `nil` if this is not a boolean.
    def to_b? : Bool?
      target = uninitialized Bool
      Lib.ucl_object_toboolean_safe(@ptr, pointerof(target)) ? target : nil
    end

    # Safely extracts the string value, returning `nil` if this is not a string.
    def to_s? : String?
      target = uninitialized UInt8*
      if Lib.ucl_object_tostring_safe(@ptr, pointerof(target))
        target.null? ? nil : String.new(target)
      end
    end

    # Looks up a child object by key. Raises `Ucl::Error` if the key is not found.
    #
    # ```
    # obj = Ucl.parse(%{host = "localhost";})
    # obj["host"].to_s # => "localhost"
    # obj["missing"]   # raises Ucl::Error
    # ```
    def [](key : String) : Object
      self[key]? || raise Error.new("Key not found: #{key}")
    end

    # Looks up a child object by key, returning `nil` if not found.
    def []?(key : String) : Object?
      ptr = Lib.ucl_object_lookup(@ptr, key.to_unsafe)
      ptr.null? ? nil : Object.new(ptr, owned: false)
    end

    # Accesses an array element by index. Raises `Ucl::Error` if out of bounds.
    #
    # ```
    # obj = Ucl.parse(%{items = ["a", "b", "c"];})
    # obj["items"][1].to_s # => "b"
    # ```
    def [](index : Int) : Object
      self[index]? || raise Error.new("Index out of bounds: #{index}")
    end

    # Accesses an array element by index, returning `nil` if out of bounds.
    def []?(index : Int) : Object?
      ptr = Lib.ucl_array_find_index(@ptr, index.to_u32)
      ptr.null? ? nil : Object.new(ptr, owned: false)
    end

    # Looks up a nested value using dot-separated path notation.
    # Raises `Ucl::Error` if the path is not found.
    #
    # ```
    # obj = Ucl.parse(%{server { host = "localhost"; }})
    # obj.at("server.host").to_s # => "localhost"
    # ```
    def at(path : String) : Object
      at?(path) || raise Error.new("Path not found: #{path}")
    end

    # Looks up a nested value using dot-separated path notation,
    # returning `nil` if not found.
    def at?(path : String) : Object?
      ptr = Lib.ucl_object_lookup_path(@ptr, path.to_unsafe)
      ptr.null? ? nil : Object.new(ptr, owned: false)
    end

    # Looks up a nested value using a custom path separator character.
    #
    # ```
    # obj.at?("server/host", '/') # use '/' instead of '.'
    # ```
    def at?(path : String, separator : Char) : Object?
      ptr = Lib.ucl_object_lookup_path_char(@ptr, path.to_unsafe, separator.ord.to_u8)
      ptr.null? ? nil : Object.new(ptr, owned: false)
    end

    # Returns the key name of this object within its parent, or `nil`
    # if this is a top-level or array element.
    def key : String?
      ptr = Lib.ucl_object_key(@ptr)
      ptr.null? ? nil : String.new(ptr)
    end

    # Yields each child element of this object or array.
    #
    # For objects, yields each key-value entry (use `#key` on the yielded
    # object to get the key name). For arrays, yields each element in order.
    #
    # Uses the libucl safe iterator pattern internally.
    def each(& : Object ->) : Nil
      iter = Lib.ucl_object_iterate_new(@ptr)
      return if iter.null?
      begin
        loop do
          cur = Lib.ucl_object_iterate_safe(iter, true)
          break if cur.null?
          yield Object.new(cur, owned: false)
        end
      ensure
        Lib.ucl_object_iterate_free(iter)
      end
    end

    # Returns the number of children (keys for objects, elements for arrays).
    #
    # For arrays, uses the O(1) `ucl_array_size`. For objects, counts
    # by iterating.
    def size : Int32
      if array?
        Lib.ucl_array_size(@ptr).to_i32
      else
        count = 0
        each { count += 1 }
        count
      end
    end

    # Returns the first element of an array. Raises `Ucl::Error` if the array is empty.
    def first : Object
      ptr = Lib.ucl_array_head(@ptr)
      raise Error.new("Empty array") if ptr.null?
      Object.new(ptr, owned: false)
    end

    # Returns the first element of an array, or `nil` if empty.
    def first? : Object?
      ptr = Lib.ucl_array_head(@ptr)
      ptr.null? ? nil : Object.new(ptr, owned: false)
    end

    # Returns the last element of an array. Raises `Ucl::Error` if the array is empty.
    def last : Object
      ptr = Lib.ucl_array_tail(@ptr)
      raise Error.new("Empty array") if ptr.null?
      Object.new(ptr, owned: false)
    end

    # Returns the last element of an array, or `nil` if empty.
    def last? : Object?
      ptr = Lib.ucl_array_tail(@ptr)
      ptr.null? ? nil : Object.new(ptr, owned: false)
    end

    # Serializes this object tree to a string in the specified format.
    #
    # Available formats: `Config` (UCL), `JSON`, `JSONCompact`, `YAML`.
    # Defaults to `Config` (human-readable UCL format).
    #
    # Raises `Ucl::Error` if emission fails.
    def emit(format : Lib::UclEmitter = Lib::UclEmitter::Config) : String
      ptr = Lib.ucl_object_emit(@ptr, format)
      raise Error.new("Failed to emit UCL object") if ptr.null?
      result = String.new(ptr)
      LibC.free(ptr.as(Void*))
      result
    end

    # Serializes to formatted JSON.
    def to_json : String
      emit(Lib::UclEmitter::JSON)
    end

    # Serializes to compact (single-line) JSON.
    def to_compact_json : String
      emit(Lib::UclEmitter::JSONCompact)
    end

    # Serializes to UCL config format (the default human-readable format).
    def to_config : String
      emit(Lib::UclEmitter::Config)
    end

    # Serializes to YAML format.
    def to_yaml_string : String
      emit(Lib::UclEmitter::YAML)
    end

    # Recursively converts the entire UCL tree to native Crystal types.
    #
    # Returns an `AnyValue` (`Nil | Bool | Int64 | Float64 | String |
    # Array(AnyValue) | Hash(String, AnyValue)`).
    #
    # ```
    # obj = Ucl.parse(%{name = "app"; port = 8080;})
    # native = obj.to_any
    # native.as(Hash)["name"] # => "app"
    # ```
    def to_any : AnyValue
      case type
      when .null?
        nil
      when .boolean?
        to_b
      when .int?
        to_i
      when .float?, .time?
        to_f
      when .string?
        to_s
      when .array?
        arr = [] of AnyValue
        each { |obj| arr << obj.to_any }
        arr
      when .object?
        hash = {} of String => AnyValue
        each do |obj|
          if k = obj.key
            hash[k] = obj.to_any
          end
        end
        hash
      else
        to_s
      end
    end

    # Creates a new owned UCL object from a Crystal integer.
    def self.from(value : Int) : Object
      Object.new(Lib.ucl_object_fromint(value.to_i64), owned: true)
    end

    # Creates a new owned UCL object from a Crystal float.
    def self.from(value : Float) : Object
      Object.new(Lib.ucl_object_fromdouble(value.to_f64), owned: true)
    end

    # Creates a new owned UCL object from a Crystal boolean.
    def self.from(value : Bool) : Object
      Object.new(Lib.ucl_object_frombool(value), owned: true)
    end

    # Creates a new owned UCL object from a Crystal string.
    def self.from(value : String) : Object
      Object.new(Lib.ucl_object_fromstring(value.to_unsafe), owned: true)
    end

    # Creates a new owned UCL null object.
    def self.from(value : Nil) : Object
      Object.new(Lib.ucl_object_typed_new(Lib::UclType::Null), owned: true)
    end

    # Creates a new empty UCL object (key-value mapping).
    #
    # ```
    # obj = Ucl::Object.new_object
    # obj["name"] = "myapp"
    # obj["port"] = 8080
    # ```
    def self.new_object : Object
      Object.new(Lib.ucl_object_typed_new(Lib::UclType::Object), owned: true)
    end

    # Creates a new empty UCL array.
    #
    # ```
    # arr = Ucl::Object.new_array
    # arr << "one"
    # arr << "two"
    # ```
    def self.new_array : Object
      Object.new(Lib.ucl_object_typed_new(Lib::UclType::Array), owned: true)
    end

    # Sets a key to a `Ucl::Object` value. Replaces any existing value
    # for the key.
    def []=(key : String, value : Object) : Object
      # Ref the child so both the parent tree and the Crystal wrapper can unref independently
      Lib.ucl_object_ref(value.to_unsafe)
      Lib.ucl_object_insert_key(@ptr, value.to_unsafe, key.to_unsafe, 0_u64, true)
      value
    end

    # Sets a key to a primitive Crystal value (converted to UCL automatically).
    def []=(key : String, value : Int | Float | Bool | String?) : Object
      child = Object.from(value)
      self[key] = child
    end

    # Appends a `Ucl::Object` to this array.
    def <<(value : Object) : self
      Lib.ucl_object_ref(value.to_unsafe)
      Lib.ucl_array_append(@ptr, value.to_unsafe)
      self
    end

    # Appends a primitive Crystal value to this array (converted to UCL automatically).
    def <<(value : Int | Float | Bool | String?) : self
      self << Object.from(value)
    end

    # Deletes a key from this object. Returns `true` if the key existed.
    def delete(key : String) : Bool
      Lib.ucl_object_delete_key(@ptr, key.to_unsafe)
    end

    # Merges another object's keys into this object.
    #
    # When *copy* is `true` (the default), values are deep-copied.
    # Returns `true` on success.
    def merge!(other : Object, copy : Bool = true) : Bool
      Lib.ucl_object_merge(@ptr, other.to_unsafe, copy)
    end

    # Returns `true` if both objects have equal structure and values.
    def ==(other : Object) : Bool
      Lib.ucl_object_compare(@ptr, other.to_unsafe) == 0
    end

    # Creates a shallow duplicate by incrementing the reference count.
    #
    # Both the original and the duplicate share the same underlying data.
    # For an independent copy, use `#deep_copy`.
    def dup : Object
      ptr = Lib.ucl_object_ref(@ptr)
      Object.new(ptr, owned: true)
    end

    # Creates a deep copy of this object tree. The copy is fully independent
    # of the original.
    def deep_copy : Object
      ptr = Lib.ucl_object_copy(@ptr)
      raise Error.new("Failed to copy UCL object") if ptr.null?
      Object.new(ptr, owned: true)
    end

    # Returns the merge priority of this object.
    def priority : UInt32
      Lib.ucl_object_get_priority(@ptr).to_u32
    end

    # Sets the merge priority of this object.
    def priority=(value : UInt32)
      Lib.ucl_object_set_priority(@ptr, value)
    end

    # Sorts the keys of this object in place.
    def sort_keys!(how : Lib::UclObjectKeysSortFlags = Lib::UclObjectKeysSortFlags::Default)
      Lib.ucl_object_sort_keys(@ptr, how)
    end

    # Validates this object against a UCL schema. Returns `true` if valid.
    def validate(schema : Object) : Bool
      Lib.ucl_object_validate(schema.to_unsafe, @ptr, nil)
    end

    # Validates this object against a UCL schema.
    # Raises `Ucl::Error` with the validation error message if invalid.
    def validate!(schema : Object) : Bool
      err = uninitialized Lib::UclSchemaError
      result = Lib.ucl_object_validate(schema.to_unsafe, @ptr, pointerof(err))
      unless result
        msg = String.new(err.msg.to_unsafe, err.msg.to_slice.index(0_u8) || 128)
        raise Error.new("Schema validation failed: #{msg}")
      end
      true
    end

    # Returns the raw `ucl_object_t` pointer for interop with the C library.
    def to_unsafe : Lib::UclObjectT*
      @ptr
    end
  end
end
