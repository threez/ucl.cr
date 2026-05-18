require "../src/ucl"

config_path = File.join(__DIR__, "fbsd_pkg.conf")

# =============================================================================
# Untyped: parse and inspect using Ucl::Object directly
# =============================================================================

puts "=== Untyped parsing ==="
puts

obj = Ucl.parse_file(config_path)

obj.each do |repo|
  name = repo.key
  puts "Repository: #{name}"

  repo.each do |field|
    puts "  #{field.key} = #{field.to_s_forced} (#{field.type_name})"
  end

  puts
end

# =============================================================================
# Typed: deserialize into Crystal structs using Ucl::Serializable
# =============================================================================

struct Repository
  include Ucl::Serializable

  property url : String
  property mirror_type : String
  property signature_type : String
  property fingerprints : String

  @[Ucl::Field(key: "enabled")]
  property? enabled : Bool = true
end

puts "=== Typed parsing ==="
puts

repos = Hash(String, Repository).from_ucl_file(config_path)

repos.each do |name, repo|
  puts "Repository: #{name}"
  puts "  url:            #{repo.url}"
  puts "  mirror_type:    #{repo.mirror_type}"
  puts "  signature_type: #{repo.signature_type}"
  puts "  fingerprints:   #{repo.fingerprints}"
  puts "  enabled:        #{repo.enabled?}"
  puts
end

# =============================================================================
# Roundtrip: serialize typed struct back to UCL config format
# =============================================================================

puts "=== Roundtrip to UCL config ==="
puts
puts repos.to_ucl.to_config
