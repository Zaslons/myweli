# Does the `ignore` on .github/dependabot.yml's docker entry keep Dependabot on
# stable `dart` tags? Answered with Dependabot's OWN docker classes, not a
# re-implementation of them.
#
# Design: docs/design/backend-dependabot-docker-stable.md §4. Not run in CI:
# backend/test/infra/dart_sdk_pin_test.dart enforces the shape this proves.
# Run it again before changing that shape, or when Dependabot changes.
#
# Inputs (read-only fetches, into a fresh directory; the commit is the updater
# image a Dependabot run's log names — `dependabot-updater-docker:<sha>`):
#
#   SHA=968bde86f9e0041abdff5ab3b613f18eeefec0df; mkdir -p dbc
#   for f in tag version requirement; do
#     gh api "repos/dependabot/dependabot-core/contents/docker/lib/dependabot/docker/$f.rb?ref=$SHA" \
#       -H 'Accept: application/vnd.github.raw' > "dbc/$f.rb"
#   done
#   TOK=$(curl -sS 'https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/dart:pull' \
#     | python3 -I -c 'import json,sys;print(json.load(sys.stdin)["token"])')
#   curl -sS -H "Authorization: Bearer $TOK" 'https://registry-1.docker.io/v2/library/dart/tags/list?n=10000' \
#     | python3 -I -c 'import json,sys;print("\n".join(json.load(sys.stdin)["tags"]))' > dart-tags.txt
#
# Run (from the repo root; --no-ignore is the control, which must pick the beta):
#
#   ruby tool/dependabot_docker_ignore_probe.rb dbc dart-tags.txt [--no-ignore]
#
# The stubs below stand in for sorbet-runtime and for common/lib/dependabot/
# {version,requirement}.rb, which are thin Gem::Version / Gem::Requirement
# subclasses: the ordering and the operators under test are RubyGems' own.

require "yaml"

module T
  module Sig; def sig(*); end; end
  module Helpers; def abstract!; end; end
  def self.must(x); x; end
  def self.let(x, *_); x; end
  def self.cast(x, *_); x; end
  def self.nilable(*); end
  def self.any(*); end
  def self.type_alias; end
  module Array; def self.[](*); end; end
  module Boolean; end
end

module Dependabot
  module Experiments; def self.enabled?(*); false; end; end
  module Utils
    def self.register_version_class(*); end
    def self.register_requirement_class(*); end
  end
  class Version < Gem::Version
    def self.correct?(v)
      return true if v.is_a?(Gem::Version)

      super(v.to_s)
    end
  end
  class Requirement < Gem::Requirement; end
  module Docker
    class FileParser; DIGEST = /^sha256:[0-9a-f]{64}$/.freeze; end
  end
end

core_dir, tags_file = ARGV.reject { |a| a.start_with?("--") }
abort "usage: ruby #{$PROGRAM_NAME} <dependabot-core docker dir> <tags file> [--no-ignore]" unless core_dir && tags_file

%w(tag version requirement).each do |f|
  src = File.read(File.join(core_dir, "#{f}.rb"), encoding: "UTF-8")
  eval(src.lines.grep_v(/^require /).join, binding, "#{f}.rb") # rubocop:disable Security/Eval
end

TAG = Dependabot::Docker::Tag
VERSION = Dependabot::Docker::Version
REQUIREMENT = Dependabot::Docker::Requirement

config = YAML.safe_load(File.read(File.join(__dir__, "..", ".github", "dependabot.yml"), encoding: "UTF-8"))
entry = config.fetch("updates").find do |u|
  u["package-ecosystem"] == "docker" && [u["directory"], *u["directories"]].include?("/backend")
end
abort "no docker entry for /backend in .github/dependabot.yml" unless entry

ranges =
  if ARGV.include?("--no-ignore")
    []
  else
    (entry["ignore"] || []).select { |r| File.fnmatch(r["dependency-name"].to_s, "dart") }
                           .flat_map { |r| r["versions"] || [">= 0"] }
  end
REQS = ranges.flat_map { |s| REQUIREMENT.requirements_array(s) }

def version_of(tag)
  VERSION.new(tag.numeric_version)
end

# update_checker.rb#filter_ignored
def ignored?(tag)
  REQS.any? { |r| r.satisfied_by?(version_of(tag)) }
end

puts "ignore `versions` for dart: #{ranges.empty? ? '(none)' : ranges.join(' | ')}"
puts
puts "1. Which tags are ignored (`compared as` is the release_part a requirement is tested on)"
%w(
  3.15.0-118.1.beta 3.14.0-1.0.dev 3.14.0-315.3.beta 3.14.0-0.1.dev 3.20.0-5.1.beta 4.0.0-12.1.beta
  3.14.0-0.0.dev 3.21.0-5.1.beta
  3.13.7 3.13.8 3.14 3.14.0 3.14.1 3.15.0 3.15.9 3.20.0 4.0.0 4.0.1
).each do |name|
  tag = TAG.new(name)
  printf("   %-20s compared as %-20s pre-release? %-5s ignored: %s\n",
         name, version_of(tag).release_part, tag.looks_like_prerelease?, ignored?(tag))
end

# update_checker.rb#fetch_latest_tag without the registry: comparable_tags_from_registry
# (original_components is empty for a plain `3.13.7`) -> remove_version_downgrades ->
# remove_more_precise_tags -> remove_prereleases -> filter_ignored -> sort_tags; the
# highest survivor. select_tag_with_precision may then swap it for a same-version
# tag of the pin's precision with the same digest — never for another version.
def pick(tags, current, current_counts_as_prerelease)
  c = tags.select { |t| t.comparable_to?(current) }
  c = c.select { |t| version_of(t) >= version_of(current) }
  c = c.select { |t| t.precision <= current.precision } if current.format == :normal && current.precision <= 2
  c = c.reject(&:looks_like_prerelease?) unless current_counts_as_prerelease
  c = c.reject { |t| ignored?(t) }
  c.max_by { |t| [version_of(t), t.same_precision?(current) ? 1 : 0] }&.name || current.name
end

tags = File.readlines(tags_file).map(&:strip).reject(&:empty?).map { |n| TAG.new(n) }
current = TAG.new("3.13.7")
puts
puts "2. Replay on #{tags.size} tags, pinned #{current.name}"
puts "   `latest` heuristic broken (3.13.7 read as a pre-release, as on 2026-11-12): #{pick(tags, current, true)}"
puts "   `latest` heuristic working:                                                 #{pick(tags, current, false)}"
