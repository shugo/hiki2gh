# frozen_string_literal: true

require "cgi"
require "fileutils"
require_relative "hiki2gh/version"

module Hiki2md
  class Error < StandardError; end

  class HikiDocument
    BLOCK_RE = /^(?:\
(?<comment>\/\/.*)|\
(?<headline>!+.*)|\
(?<unordered_list>\*+.*)|\
(?<ordered_list>#+.*)|\
(?<definition_list>:.*?:.*)|\
(?<preformatted_text>[ \t]+.*(\n[ \t].*)*)|\
(?<table>(\|\|.*\n)+)|\
(?<body>).*
)/

    INILINE_RE = /\
(?<link>\[\[.*?\]\])|\
(?<emphasis>'''?.*?'''?)|\
(?<strike>==.*?==)|\
(?<plugin>\{\{*?\}\})
/
    
    def initialize(src)
      @src = src
    end

    def to_markdown
      @src.gsub(BLOCK_RE) { |s|
        case
        when $~[:comment]
          s.sub!(/^\/\//, "")
          "<!-- " + convert_inline(s) + "-->"
        when $~[:headline]
          s.sub!(/^!+/) { |t| "#" * t.size }
          convert_inline(s)
        when $~[:unordered_list]
          s.sub!(/^\*+/) { |t|
            "    " * (t.size - 1) + "* "
          }
          convert_inline(s)
        when $~[:ordered_list]
          s.sub!(/^#+/) { |t|
            "    " * (t.size - 1) + "1. "
          }
          convert_inline(s)
        when $~[:definition_list]
          s.sub!(/^:(.*?):/) {
            "* " + $1 + ": "
          }
          convert_inline(s)
        when $~[:preformatted_text]
          indentation = s.slice(/^[ \t]+/)
          s.gsub!(/^#{indentation}/, "")
          "```\n" + convert_inline(s) + "\n```"
        when $~[:table]
          table = s.each_line.map { |line|
            line.chomp.split(/ *\|\|!? */).drop(1)
          }
          table[1, 0] = [Array.new(table.first.size, "---")]
          t = table.map { |row|
            "| " + row.join(" | ") + " |\n"
          }.join
          convert_inline(t)
        else
          convert_inline(s)
        end
      }
    end

    def convert_inline(str)
      str.gsub(INILINE_RE) { |s|
        case
        when $~[:link]
          label, url = s.slice(/\[\[(.*?)\]\]/, 1).split(/\|/)
          "[#{label}]" + (url ? "(#{url})" : "")
        when $~[:emphasis]
          s.gsub(/'''?/, "**")
        when $~[:strike]
          s.gsub(/==/, "~~")
        when $~[:plugin]
          s
        else
          s
        end
      }
    end
  end

  class HikiFarm
    def initialize(path)
      @path = path
    end

    def export(dst_path)
      Dir.glob("#{path}/*") do |wiki_path|
        wiki_name = File.basename(wiki_path)
        Dir.mkdir_p(File.expand_path(wiki_name, dst_path))
        attach_prefix = "#{wiki_path}/cahce/attach"
        Dir.glob("#{attach_prefix}/**/*") do |file|
          p file[attach_prefix..-1]
        end
      end
    end
  end
end
