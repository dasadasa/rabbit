require 'rabbit/utils'

Rabbit::Converter.keep_kcode("EUC-JP") do
  begin
    require 'migemo'
  rescue LoadError
  end
end

module Rabbit
  class Searcher
    @@migemo_static_dict = nil
    def initialize(canvas)
      @canvas = canvas
    end

    def regexp(text)
      unless text == @text
        @text = text
        @regexp = nil
      end
      @regexp ||= internal_regexp
    end

    private
    def internal_regexp
      if migemo_available?
        migemo_regexp
      else
        /#{@text}/iu
      end
    end

    def migemo_regexp
      text = Converter.to_eucjp_from_utf8(@text)
      segments = migemo_split_text(text)
      if segments.size <= 1
        regexp_str = migemo_generate_regexp_str(text, false)
      else
        regexp_str1 = migemo_generate_regexp_str(text, true)
        regexp_str2 = segments.collect do |pattern|
          migemo_generate_regexp_str(pattern, true)
        end.join
        regexp_str = [regexp_str1, regexp_str2].join("|")
      end
      /#{Converter.to_utf8_from_eucjp(regexp_str)}/u
    end

    def migemo_generate_regexp_str(pattern, with_paren)
      Converter.keep_kcode("EUC-JP") do
        migemo = Migemo.new(@@migemo_static_dict, pattern)
        migemo.with_paren = with_paren
        migemo.regex
      end
    end

    def migemo_split_text(text)
      text.scan(/[A-Z]?[^A-Z]+|[A-Z]+/e)
    end

    def migemo_available?
      defined?(::Migemo) and have_migemo_static_dict?
    end

    def have_migemo_static_dict?
      @@migemo_static_dict ||= search_migemo_static_dict
      not @@migemo_static_dict.nil?
    end

    def search_migemo_static_dict
      default_base_name = "migemo-dict"
      [
       File.join("", "usr", "local", "share"),
       File.join("", "usr", "share"),
      ].each do |target|
        if File.directory?(target)
          [
           File.join(target, default_base_name),
           File.join(target, "migemo", default_base_name),
          ].each do |guess|
            return MigemoStaticDict.new(guess) if File.readable?(guess)
          end
        elsif File.readable?(target)
          return MigemoStaticDict.new(target)
        end
      end
      nil
    end
  end
end