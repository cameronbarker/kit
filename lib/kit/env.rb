# frozen_string_literal: true

module Kit
  module Env
    ROOT = File.expand_path("../..", __dir__)
    DEFAULT_PATH = File.join(ROOT, ".env")

    # Load KEY=VALUE pairs from a dotenv-style file into ENV.
    # Existing ENV values win (shell exports override .env).
    def self.load!(path: DEFAULT_PATH, into: ENV)
      return false unless File.file?(path)

      File.foreach(path) do |line|
        line = line.strip
        next if line.empty? || line.start_with?("#")

        key, separator, value = line.partition("=")
        next if separator.empty?

        key = key.strip
        next if key.empty?
        next if into.key?(key)

        into[key] = unquote(value.strip)
      end

      true
    end

    def self.unquote(value)
      if (value.start_with?('"') && value.end_with?('"')) ||
         (value.start_with?("'") && value.end_with?("'"))
        return value[1..-2]
      end

      value
    end
    private_class_method :unquote
  end
end
