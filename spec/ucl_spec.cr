require "./spec_helper"

class ServerConfig
  include Ucl::Serializable

  property host : String
  property port : Int32
  property tls : Bool = false
end

class DatabaseConfig
  include Ucl::Serializable

  @[Ucl::Field(key: "connection_string")]
  property dsn : String
  property pool_size : Int32 = 5
  property read_only : Bool = false
end

class AppConfig
  include Ucl::Serializable

  property name : String
  property server : ServerConfig
  property database : DatabaseConfig
  property tags : Array(String) = [] of String
  property metadata : Hash(String, String) = {} of String => String
end

class OptionalConfig
  include Ucl::Serializable

  property required_field : String
  property optional_string : String?
  property optional_int : Int32?
  property with_default : String = "default_value"
end

class StrictConfig
  include Ucl::Serializable
  include Ucl::Serializable::Strict

  property name : String
end

class NumericConfig
  include Ucl::Serializable

  property small : Int8
  property medium : Int16
  property large : Int32
  property huge : Int64
  property float32 : Float32
  property float64 : Float64
end

class PresenceConfig
  include Ucl::Serializable

  @value_present : Bool = false

  @[Ucl::Field(presence: true)]
  property value : String?
end

class IgnoreConfig
  include Ucl::Serializable

  property visible : String

  @[Ucl::Field(ignore: true)]
  property ignored : String = "default"
end

class ArrayOfObjects
  include Ucl::Serializable

  property servers : Array(ServerConfig)
end

class UnionConfig
  include Ucl::Serializable

  property value : Int32 | String
end

describe Ucl do
  describe ".parse" do
    it "parses a simple key-value string" do
      obj = Ucl.parse(%{name = "Crystal";})
      obj["name"].to_s.should eq("Crystal")
    end

    it "parses multiple key-value pairs" do
      obj = Ucl.parse(%{host = "localhost"; port = 8080;})
      obj["host"].to_s.should eq("localhost")
      obj["port"].to_i.should eq(8080)
    end

    it "parses nested objects" do
      obj = Ucl.parse(%{
        server {
          host = "127.0.0.1";
          port = 443;
        }
      })
      obj["server"]["host"].to_s.should eq("127.0.0.1")
      obj["server"]["port"].to_i.should eq(443)
    end

    it "parses arrays" do
      obj = Ucl.parse(%{ports = [80, 443, 8080];})
      arr = obj["ports"]
      arr.array?.should be_true
      arr.size.should eq(3)
      arr[0].to_i.should eq(80)
      arr[1].to_i.should eq(443)
      arr[2].to_i.should eq(8080)
    end

    it "parses boolean values" do
      obj = Ucl.parse(%{enabled = true; disabled = false;})
      obj["enabled"].to_b.should be_true
      obj["disabled"].to_b.should be_false
    end

    it "parses float values" do
      obj = Ucl.parse(%{pi = 3.14;})
      obj["pi"].to_f.should be_close(3.14, 0.001)
    end

    it "parses null values" do
      obj = Ucl.parse(%{nothing = null;})
      obj["nothing"].null?.should be_true
    end
  end

  describe ".parse_file" do
    it "parses a UCL file" do
      path = File.tempname("ucl_test", ".conf")
      File.write(path, %{
        app {
          name = "test";
          version = 1;
        }
      })
      begin
        obj = Ucl.parse_file(path)
        obj["app"]["name"].to_s.should eq("test")
        obj["app"]["version"].to_i.should eq(1)
      ensure
        File.delete(path)
      end
    end
  end

  describe Ucl::Object do
    describe "#type" do
      it "reports correct types" do
        obj = Ucl.parse(%{
          str = "hello";
          num = 42;
          flt = 1.5;
          flag = true;
          arr = [1, 2];
          sub { key = "val"; }
          nothing = null;
        })
        obj["str"].string?.should be_true
        obj["num"].int?.should be_true
        obj["flt"].float?.should be_true
        obj["flag"].boolean?.should be_true
        obj["arr"].array?.should be_true
        obj["sub"].object?.should be_true
        obj["nothing"].null?.should be_true
      end
    end

    describe "#type_name" do
      it "returns string representation of type" do
        obj = Ucl.parse(%{val = 42;})
        obj["val"].type_name.should eq("integer")
      end
    end

    describe "safe value extraction" do
      it "returns value on matching type" do
        obj = Ucl.parse(%{num = 42;})
        obj["num"].to_i?.should eq(42)
      end

      it "returns nil on type mismatch" do
        obj = Ucl.parse(%{str = "hello";})
        obj["str"].to_i?.should be_nil
      end

      it "safely extracts strings" do
        obj = Ucl.parse(%{name = "world";})
        obj["name"].to_s?.should eq("world")
      end

      it "safely extracts booleans" do
        obj = Ucl.parse(%{flag = true;})
        obj["flag"].to_b?.should be_true
      end

      it "safely extracts floats" do
        obj = Ucl.parse(%{val = 2.5;})
        val = obj["val"].to_f?
        val.should_not be_nil
        val.not_nil!.should be_close(2.5, 0.001)
      end
    end

    describe "#[]?" do
      it "returns nil for missing keys" do
        obj = Ucl.parse(%{a = 1;})
        obj["b"]?.should be_nil
      end

      it "returns nil for out-of-bounds index" do
        obj = Ucl.parse(%{arr = [1];})
        obj["arr"][5]?.should be_nil
      end
    end

    describe "#[]" do
      it "raises on missing key" do
        obj = Ucl.parse(%{a = 1;})
        expect_raises(Ucl::Error, "Key not found") { obj["missing"] }
      end

      it "raises on out-of-bounds index" do
        obj = Ucl.parse(%{arr = [1];})
        expect_raises(Ucl::Error, "Index out of bounds") { obj["arr"][99] }
      end
    end

    describe "#at / #at?" do
      it "looks up by dot-notation path" do
        obj = Ucl.parse(%{
          a { b { c = 42; } }
        })
        obj.at("a.b.c").to_i.should eq(42)
      end

      it "returns nil for missing path" do
        obj = Ucl.parse(%{a = 1;})
        obj.at?("x.y.z").should be_nil
      end
    end

    describe "#key" do
      it "returns the key of an iterated object" do
        obj = Ucl.parse(%{alpha = 1; beta = 2;})
        keys = obj.map(&.key.not_nil!)
        keys.should contain("alpha")
        keys.should contain("beta")
      end
    end

    describe "#each" do
      it "iterates over object keys" do
        obj = Ucl.parse(%{x = 1; y = 2; z = 3;})
        count = 0
        obj.each { count += 1 }
        count.should eq(3)
      end

      it "iterates over array elements" do
        obj = Ucl.parse(%{arr = [10, 20, 30];})
        values = obj["arr"].map(&.to_i)
        values.should eq([10_i64, 20_i64, 30_i64])
      end
    end

    describe "#size" do
      it "returns array size" do
        obj = Ucl.parse(%{arr = [1, 2, 3, 4];})
        obj["arr"].size.should eq(4)
      end

      it "returns object size" do
        obj = Ucl.parse(%{a = 1; b = 2;})
        obj.size.should eq(2)
      end
    end

    describe "#first / #last" do
      it "returns first and last array elements" do
        obj = Ucl.parse(%{arr = [10, 20, 30];})
        obj["arr"].first.to_i.should eq(10)
        obj["arr"].last.to_i.should eq(30)
      end
    end

    describe "emission" do
      it "emits JSON" do
        obj = Ucl.parse(%{name = "test"; value = 42;})
        json = obj.to_json
        json.should contain("\"name\"")
        json.should contain("\"test\"")
        json.should contain("42")
      end

      it "emits compact JSON" do
        obj = Ucl.parse(%{a = 1;})
        compact = obj.to_compact_json
        compact.should contain("\"a\":1")
      end

      it "emits config format" do
        obj = Ucl.parse(%{key = "value";})
        config = obj.to_config
        config.should contain("key")
        config.should contain("value")
      end

      it "emits YAML format" do
        obj = Ucl.parse(%{key = "value";})
        yaml = obj.to_yaml_string
        yaml.should contain("key")
        yaml.should contain("value")
      end
    end

    describe "#to_any" do
      it "converts simple values" do
        obj = Ucl.parse(%{num = 42;})
        any = obj.to_any.as(Hash(String, Ucl::AnyValue))
        any["num"].should eq(42_i64)
      end

      it "converts nested structures" do
        obj = Ucl.parse(%{
          config {
            items = [1, 2, 3];
            enabled = true;
          }
        })
        any = obj.to_any.as(Hash(String, Ucl::AnyValue))
        config = any["config"].as(Hash(String, Ucl::AnyValue))
        items = config["items"].as(Array(Ucl::AnyValue))
        items.should eq([1_i64, 2_i64, 3_i64] of Ucl::AnyValue)
        config["enabled"].should eq(true)
      end

      it "converts null values" do
        obj = Ucl.parse(%{n = null;})
        any = obj.to_any.as(Hash(String, Ucl::AnyValue))
        any["n"].should be_nil
      end
    end

    describe "construction" do
      it "creates integer objects" do
        obj = Ucl::Object.from(42)
        obj.int?.should be_true
        obj.to_i.should eq(42)
      end

      it "creates float objects" do
        obj = Ucl::Object.from(3.14)
        obj.float?.should be_true
        obj.to_f.should be_close(3.14, 0.001)
      end

      it "creates boolean objects" do
        obj = Ucl::Object.from(true)
        obj.boolean?.should be_true
        obj.to_b.should be_true
      end

      it "creates string objects" do
        obj = Ucl::Object.from("hello")
        obj.string?.should be_true
        obj.to_s.should eq("hello")
      end

      it "creates null objects" do
        obj = Ucl::Object.from(nil)
        obj.null?.should be_true
      end

      it "builds objects with keys" do
        obj = Ucl::Object.new_object
        obj["name"] = "test"
        obj["port"] = 8080
        obj["name"].to_s.should eq("test")
        obj["port"].to_i.should eq(8080)
      end

      it "builds arrays" do
        arr = Ucl::Object.new_array
        arr << 1
        arr << 2
        arr << 3
        arr.size.should eq(3)
        arr[0].to_i.should eq(1)
        arr[2].to_i.should eq(3)
      end

      it "emits constructed objects" do
        obj = Ucl::Object.new_object
        obj["key"] = "value"
        json = obj.to_compact_json
        json.should contain("\"key\"")
        json.should contain("\"value\"")
      end
    end

    describe "#delete" do
      it "removes a key from an object" do
        obj = Ucl.parse(%{a = 1; b = 2;})
        obj.delete("a").should be_true
        obj["a"]?.should be_nil
        obj["b"].to_i.should eq(2)
      end
    end

    describe "#==" do
      it "compares equal objects" do
        a = Ucl::Object.from(42)
        b = Ucl::Object.from(42)
        (a == b).should be_true
      end

      it "compares unequal objects" do
        a = Ucl::Object.from(1)
        b = Ucl::Object.from(2)
        (a == b).should be_false
      end
    end

    describe "#dup" do
      it "creates a reference copy" do
        original = Ucl::Object.from(42)
        copy = original.dup
        copy.to_i.should eq(42)
      end
    end

    describe "#deep_copy" do
      it "creates an independent copy" do
        original = Ucl.parse(%{a = 1; b = 2;})
        copy = original.deep_copy
        copy["a"].to_i.should eq(1)
        copy["b"].to_i.should eq(2)
      end
    end
  end

  describe Ucl::Parser do
    it "raises ParseError on invalid input" do
      expect_raises(Ucl::ParseError) do
        Ucl.parse("= = = not valid ucl <<<")
      end
    end

    it "provides line and column in parse errors" do
      begin
        Ucl.parse("valid = 1;\n= = = invalid\n")
      rescue e : Ucl::ParseError
        e.line.should be > 0
      end
    end

    it "supports variable substitution" do
      parser = Ucl::Parser.new
      parser.register_variable("MYVAR", "hello")
      parser.add_string(%{greeting = "$MYVAR";})
      obj = parser.parse!
      obj["greeting"].to_s.should eq("hello")
    end

    it "supports method chaining" do
      obj = Ucl::Parser.new
        .add_string(%{a = 1;})
        .parse!
      obj["a"].to_i.should eq(1)
    end
  end

  describe Ucl::Serializable do
    describe "basic deserialization" do
      it "deserializes a simple config" do
        config = ServerConfig.from_ucl(%{
          host = "localhost";
          port = 8080;
        })
        config.host.should eq("localhost")
        config.port.should eq(8080)
        config.tls.should be_false
      end

      it "deserializes with overridden defaults" do
        config = ServerConfig.from_ucl(%{
          host = "0.0.0.0";
          port = 443;
          tls = true;
        })
        config.host.should eq("0.0.0.0")
        config.port.should eq(443)
        config.tls.should be_true
      end
    end

    describe "key remapping" do
      it "uses custom key names" do
        config = DatabaseConfig.from_ucl(%{
          connection_string = "postgres://localhost/mydb";
          pool_size = 10;
        })
        config.dsn.should eq("postgres://localhost/mydb")
        config.pool_size.should eq(10)
      end
    end

    describe "nested objects" do
      it "deserializes nested structures" do
        config = AppConfig.from_ucl(%{
          name = "myapp";
          server {
            host = "0.0.0.0";
            port = 443;
            tls = true;
          }
          database {
            connection_string = "postgres://localhost/db";
          }
        })
        config.name.should eq("myapp")
        config.server.host.should eq("0.0.0.0")
        config.server.port.should eq(443)
        config.server.tls.should be_true
        config.database.dsn.should eq("postgres://localhost/db")
        config.database.pool_size.should eq(5)
      end
    end

    describe "arrays" do
      it "deserializes arrays of primitives" do
        config = AppConfig.from_ucl(%{
          name = "myapp";
          server {
            host = "localhost";
            port = 80;
          }
          database {
            connection_string = "sqlite://test.db";
          }
          tags = ["web", "api", "backend"];
        })
        config.tags.should eq(["web", "api", "backend"])
      end

      it "deserializes arrays of objects" do
        config = ArrayOfObjects.from_ucl(%{
          servers = [
            { host = "web1"; port = 80; },
            { host = "web2"; port = 8080; tls = true; }
          ];
        })
        config.servers.size.should eq(2)
        config.servers[0].host.should eq("web1")
        config.servers[0].port.should eq(80)
        config.servers[1].host.should eq("web2")
        config.servers[1].tls.should be_true
      end
    end

    describe "hash fields" do
      it "deserializes hash fields" do
        config = AppConfig.from_ucl(%{
          name = "myapp";
          server {
            host = "localhost";
            port = 80;
          }
          database {
            connection_string = "sqlite://test.db";
          }
          metadata {
            env = "production";
            region = "us-east";
          }
        })
        config.metadata["env"].should eq("production")
        config.metadata["region"].should eq("us-east")
      end
    end

    describe "optional fields" do
      it "handles nilable fields" do
        config = OptionalConfig.from_ucl(%{
          required_field = "present";
        })
        config.required_field.should eq("present")
        config.optional_string.should be_nil
        config.optional_int.should be_nil
        config.with_default.should eq("default_value")
      end

      it "fills nilable fields when present" do
        config = OptionalConfig.from_ucl(%{
          required_field = "present";
          optional_string = "here";
          optional_int = 42;
          with_default = "custom";
        })
        config.optional_string.should eq("here")
        config.optional_int.should eq(42)
        config.with_default.should eq("custom")
      end
    end

    describe "missing required fields" do
      it "raises on missing required field" do
        expect_raises(Ucl::Error, "Missing UCL attribute") do
          ServerConfig.from_ucl(%{host = "localhost";})
        end
      end
    end

    describe "numeric types" do
      it "deserializes various numeric types" do
        config = NumericConfig.from_ucl(%{
          small = 1;
          medium = 1000;
          large = 100000;
          huge = 9999999999;
          float32 = 1.5;
          float64 = 3.14159265358979;
        })
        config.small.should eq(1_i8)
        config.medium.should eq(1000_i16)
        config.large.should eq(100000_i32)
        config.huge.should eq(9999999999_i64)
        config.float32.should be_close(1.5_f32, 0.001)
        config.float64.should be_close(3.14159265358979, 0.0000001)
      end
    end

    describe "strict mode" do
      it "raises on unknown keys" do
        expect_raises(Ucl::Error, "Unknown UCL attribute") do
          StrictConfig.from_ucl(%{name = "test"; unknown = 1;})
        end
      end
    end

    describe "presence tracking" do
      it "tracks field presence" do
        config = PresenceConfig.from_ucl(%{value = "here";})
        config.value.should eq("here")
        config.@value_present.should be_true
      end

      it "tracks absent fields" do
        config = PresenceConfig.from_ucl(%{other = 1;})
        config.value.should be_nil
        config.@value_present.should be_false
      end
    end

    describe "ignored fields" do
      it "skips ignored fields" do
        config = IgnoreConfig.from_ucl(%{visible = "yes"; ignored = "no";})
        config.visible.should eq("yes")
        config.ignored.should eq("default")
      end
    end

    describe "union types" do
      it "deserializes int from union" do
        config = UnionConfig.from_ucl(%{value = 42;})
        config.value.should eq(42)
      end

      it "deserializes string from union" do
        config = UnionConfig.from_ucl(%{value = "hello";})
        config.value.should eq("hello")
      end
    end

    describe "serialization" do
      it "serializes to UCL object" do
        config = ServerConfig.from_ucl(%{
          host = "localhost";
          port = 8080;
          tls = true;
        })
        obj = config.to_ucl
        obj["host"].to_s.should eq("localhost")
        obj["port"].to_i.should eq(8080)
        obj["tls"].to_b.should be_true
      end

      it "serializes to UCL string" do
        config = ServerConfig.from_ucl(%{
          host = "localhost";
          port = 8080;
        })
        output = config.to_ucl_string
        output.should contain("host")
        output.should contain("localhost")
        output.should contain("port")
        output.should contain("8080")
      end

      it "serializes nested objects" do
        config = AppConfig.from_ucl(%{
          name = "myapp";
          server {
            host = "localhost";
            port = 80;
          }
          database {
            connection_string = "sqlite://test.db";
          }
          tags = ["a", "b"];
        })
        obj = config.to_ucl
        obj["name"].to_s.should eq("myapp")
        obj["server"]["host"].to_s.should eq("localhost")
        obj["database"]["connection_string"].to_s.should eq("sqlite://test.db")
        tags = obj["tags"]
        tags.array?.should be_true
        tags[0].to_s.should eq("a")
      end

      it "serializes with custom keys" do
        config = DatabaseConfig.from_ucl(%{
          connection_string = "postgres://localhost/db";
        })
        obj = config.to_ucl
        obj["connection_string"].to_s.should eq("postgres://localhost/db")
      end

      it "skips nil values by default" do
        config = OptionalConfig.from_ucl(%{required_field = "yes";})
        obj = config.to_ucl
        obj["required_field"].to_s.should eq("yes")
        obj["optional_string"]?.should be_nil
      end

      it "roundtrips through serialization" do
        original = AppConfig.from_ucl(%{
          name = "roundtrip";
          server {
            host = "10.0.0.1";
            port = 9090;
            tls = true;
          }
          database {
            connection_string = "mysql://db/app";
            pool_size = 20;
          }
          tags = ["prod", "us-east"];
        })
        ucl_string = original.to_ucl_string
        restored = AppConfig.from_ucl(ucl_string)
        restored.name.should eq("roundtrip")
        restored.server.host.should eq("10.0.0.1")
        restored.server.port.should eq(9090)
        restored.server.tls.should be_true
        restored.database.dsn.should eq("mysql://db/app")
        restored.database.pool_size.should eq(20)
        restored.tags.should eq(["prod", "us-east"])
      end
    end

    describe "from_ucl_file" do
      it "loads config from file" do
        path = File.tempname("ucl_serializable_test", ".conf")
        File.write(path, %{
          host = "filehost";
          port = 3000;
        })
        begin
          config = ServerConfig.from_ucl_file(path)
          config.host.should eq("filehost")
          config.port.should eq(3000)
        ensure
          File.delete(path)
        end
      end
    end
  end
end
