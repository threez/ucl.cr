module Ucl
  # On FreeBSD, libucl ships as part of the base system under the name
  # `privateucl`. On Linux and macOS it is a separate package (`libucl-dev`
  # / `brew install libucl`) linked as `ucl`.
  {% if flag?(:freebsd) %}
    @[Link("privateucl")]
  {% else %}
    @[Link("ucl")]
  {% end %}
  lib Lib
    enum UclError
      EOK       = 0
      ESyntax
      EIO
      EState
      ENested
      EUnpaired
      EMacro
      EInternal
      ESSL
      EMerge
    end

    enum UclType
      Object   = 0
      Array
      Int
      Float
      String
      Boolean
      Time
      Userdata
      Null
    end

    enum UclEmitter
      JSON        = 0
      JSONCompact
      Config
      YAML
      MsgPack
      Max
    end

    @[Flags]
    enum UclParserFlags
      Default          = 0
      KeyLowercase     = 1 << 0
      ZeroCopy         = 1 << 1
      NoTime           = 1 << 2
      NoImplicitArrays = 1 << 3
      SaveComments     = 1 << 4
      DisableMacro     = 1 << 5
      NoFileVars       = 1 << 6
    end

    @[Flags]
    enum UclStringFlags
      Raw          = 0
      Escape       = 1 << 0
      Trim         = 1 << 1
      ParseBoolean = 1 << 2
      ParseInt     = 1 << 3
      ParseDouble  = 1 << 4
      ParseTime    = 1 << 5
      ParseBytes   = 1 << 6
    end

    @[Flags]
    enum UclObjectFlags
      AllocatedKey   = 1 << 0
      AllocatedValue = 1 << 1
      NeedKeyEscape  = 1 << 2
      Ephemeral      = 1 << 3
      Multiline      = 1 << 4
      Multivalue     = 1 << 5
      Inherited      = 1 << 6
      Binary         = 1 << 7
      SQuoted        = 1 << 8
    end

    enum UclDuplicateStrategy
      Append  = 0
      Merge
      Rewrite
      Error
    end

    enum UclParseType
      UCL     = 0
      MsgPack
      CSexp
      Auto
    end

    @[Flags]
    enum UclIterateType
      Explicit = 1 << 0
      Implicit = 1 << 1
    end

    enum UclSchemaErrorCode
      OK                 = 0
      TypeMismatch
      InvalidSchema
      MissingProperty
      Constraint
      MissingDependency
      ExternalRefMissing
      ExternalRefInvalid
      InternalError
      Unknown
    end

    @[Flags]
    enum UclObjectKeysSortFlags
      Default   = 0
      ICase     = 1 << 0
      Recursive = 1 << 1
    end

    union UclValue
      iv : Int64
      sv : UInt8*
      dv : Float64
      av : Void*
      ov : Void*
      ud : Void*
    end

    struct UclObjectT
      value : UclValue
      key : UInt8*
      next : UclObjectT*
      prev : UclObjectT*
      keylen : UInt32
      len : UInt32
      ref : UInt32
      flags : UInt16
      type : UInt16
      trash_stack : StaticArray(UInt8*, 2)
    end

    struct UclSchemaError
      code : UclSchemaErrorCode
      msg : StaticArray(UInt8, 128)
      obj : UclObjectT*
    end

    type UclParser = Void

    # Parser lifecycle
    fun ucl_parser_new(flags : LibC::Int) : UclParser*
    fun ucl_parser_free(parser : UclParser*) : Void

    # Parser input
    fun ucl_parser_add_chunk(parser : UclParser*, data : UInt8*, len : LibC::SizeT) : Bool
    fun ucl_parser_add_string(parser : UclParser*, data : UInt8*, len : LibC::SizeT) : Bool
    fun ucl_parser_add_file(parser : UclParser*, filename : UInt8*) : Bool

    # Parser state
    fun ucl_parser_get_object(parser : UclParser*) : UclObjectT*
    fun ucl_parser_get_error(parser : UclParser*) : UInt8*
    fun ucl_parser_get_error_code(parser : UclParser*) : LibC::Int
    fun ucl_parser_get_column(parser : UclParser*) : LibC::UInt
    fun ucl_parser_get_linenum(parser : UclParser*) : LibC::UInt
    fun ucl_parser_clear_error(parser : UclParser*) : Void

    # Parser configuration
    fun ucl_parser_register_variable(parser : UclParser*, var : UInt8*, value : UInt8*) : Void
    fun ucl_parser_set_filevars(parser : UclParser*, filename : UInt8*, need_expand : Bool) : Bool
    fun ucl_parser_set_default_priority(parser : UclParser*, prio : LibC::UInt) : Bool

    # Object type inspection
    fun ucl_object_type(obj : UclObjectT*) : UclType
    fun ucl_object_type_to_string(type : UclType) : UInt8*
    fun ucl_object_key(obj : UclObjectT*) : UInt8*
    fun ucl_object_keyl(obj : UclObjectT*, len : LibC::SizeT*) : UInt8*

    # Object lookup
    fun ucl_object_lookup(obj : UclObjectT*, key : UInt8*) : UclObjectT*
    fun ucl_object_lookup_len(obj : UclObjectT*, key : UInt8*, klen : LibC::SizeT) : UclObjectT*
    fun ucl_object_lookup_path(obj : UclObjectT*, path : UInt8*) : UclObjectT*
    fun ucl_object_lookup_path_char(obj : UclObjectT*, path : UInt8*, sep : UInt8) : UclObjectT*

    # Value extraction (unsafe)
    fun ucl_object_toint(obj : UclObjectT*) : Int64
    fun ucl_object_todouble(obj : UclObjectT*) : Float64
    fun ucl_object_toboolean(obj : UclObjectT*) : Bool
    fun ucl_object_tostring(obj : UclObjectT*) : UInt8*
    fun ucl_object_tolstring(obj : UclObjectT*, tlen : LibC::SizeT*) : UInt8*
    fun ucl_object_tostring_forced(obj : UclObjectT*) : UInt8*

    # Value extraction (safe)
    fun ucl_object_toint_safe(obj : UclObjectT*, target : Int64*) : Bool
    fun ucl_object_todouble_safe(obj : UclObjectT*, target : Float64*) : Bool
    fun ucl_object_toboolean_safe(obj : UclObjectT*, target : Bool*) : Bool
    fun ucl_object_tostring_safe(obj : UclObjectT*, target : UInt8**) : Bool

    # Iteration
    fun ucl_object_iterate_new(obj : UclObjectT*) : Void*
    fun ucl_object_iterate_safe(iter : Void*, expand_values : Bool) : UclObjectT*
    fun ucl_object_iterate_full(iter : Void*, type : UclIterateType) : UclObjectT*
    fun ucl_object_iterate_free(iter : Void*) : Void
    fun ucl_object_iterate_reset(iter : Void*, obj : UclObjectT*) : Void*

    # Array operations
    fun ucl_array_size(top : UclObjectT*) : LibC::UInt
    fun ucl_array_find_index(top : UclObjectT*, index : LibC::UInt) : UclObjectT*
    fun ucl_array_head(top : UclObjectT*) : UclObjectT*
    fun ucl_array_tail(top : UclObjectT*) : UclObjectT*
    fun ucl_array_append(top : UclObjectT*, elt : UclObjectT*) : Bool
    fun ucl_array_prepend(top : UclObjectT*, elt : UclObjectT*) : Bool
    fun ucl_array_delete(top : UclObjectT*, elt : UclObjectT*) : UclObjectT*
    fun ucl_array_pop_first(top : UclObjectT*) : UclObjectT*
    fun ucl_array_pop_last(top : UclObjectT*) : UclObjectT*
    fun ucl_array_merge(top : UclObjectT*, elt : UclObjectT*, copy : Bool) : Bool
    fun ucl_array_index_of(top : UclObjectT*, elt : UclObjectT*) : LibC::UInt
    fun ucl_array_replace_index(top : UclObjectT*, elt : UclObjectT*, index : LibC::UInt) : UclObjectT*

    # Object construction
    fun ucl_object_new : UclObjectT*
    fun ucl_object_typed_new(type : UclType) : UclObjectT*
    fun ucl_object_new_full(type : UclType, priority : LibC::UInt) : UclObjectT*
    fun ucl_object_fromint(iv : Int64) : UclObjectT*
    fun ucl_object_fromdouble(dv : Float64) : UclObjectT*
    fun ucl_object_frombool(bv : Bool) : UclObjectT*
    fun ucl_object_fromstring(str : UInt8*) : UclObjectT*
    fun ucl_object_fromlstring(str : UInt8*, len : LibC::SizeT) : UclObjectT*
    fun ucl_object_fromstring_common(str : UInt8*, len : LibC::SizeT, flags : UclStringFlags) : UclObjectT*
    fun ucl_object_copy(other : UclObjectT*) : UclObjectT*

    # Object modification
    fun ucl_object_insert_key(top : UclObjectT*, elt : UclObjectT*, key : UInt8*, keylen : LibC::SizeT, copy_key : Bool) : Bool
    fun ucl_object_replace_key(top : UclObjectT*, elt : UclObjectT*, key : UInt8*, keylen : LibC::SizeT, copy_key : Bool) : Bool
    fun ucl_object_insert_key_merged(top : UclObjectT*, elt : UclObjectT*, key : UInt8*, keylen : LibC::SizeT, copy_key : Bool) : Bool
    fun ucl_object_delete_key(top : UclObjectT*, key : UInt8*) : Bool
    fun ucl_object_delete_keyl(top : UclObjectT*, key : UInt8*, keylen : LibC::SizeT) : Bool
    fun ucl_object_pop_key(top : UclObjectT*, key : UInt8*) : UclObjectT*
    fun ucl_object_merge(top : UclObjectT*, elt : UclObjectT*, copy : Bool) : Bool
    fun ucl_object_reserve(obj : UclObjectT*, reserved : LibC::SizeT) : Bool

    # Refcounting
    fun ucl_object_ref(obj : UclObjectT*) : UclObjectT*
    fun ucl_object_unref(obj : UclObjectT*) : Void

    # Emission
    fun ucl_object_emit(obj : UclObjectT*, emit_type : UclEmitter) : UInt8*
    fun ucl_object_emit_len(obj : UclObjectT*, emit_type : UclEmitter, len : LibC::SizeT*) : UInt8*

    # Comparison
    fun ucl_object_compare(o1 : UclObjectT*, o2 : UclObjectT*) : LibC::Int

    # Priority
    fun ucl_object_get_priority(obj : UclObjectT*) : LibC::UInt
    fun ucl_object_set_priority(obj : UclObjectT*, priority : LibC::UInt) : Void

    # Sorting
    fun ucl_object_sort_keys(obj : UclObjectT*, how : UclObjectKeysSortFlags) : Void

    # Validation
    fun ucl_object_validate(schema : UclObjectT*, obj : UclObjectT*, err : UclSchemaError*) : Bool
    fun ucl_object_validate_root(schema : UclObjectT*, obj : UclObjectT*, root : UclObjectT*, err : UclSchemaError*) : Bool
  end
end
