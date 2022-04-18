# frozen_string_literal: true

require "cgi"
require "fileutils"
require_relative "hiki2gh/version"

module Hiki2gh
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
      Dir.glob("#{@path}/*") do |wiki_path|
        wiki_name = File.basename(wiki_path)
        dst_wiki_path = File.expand_path(wiki_name, dst_path)
        FileUtils.mkdir_p(dst_wiki_path)

        attach_dir = "#{wiki_path}/cache/attach"
        if File.directory?(attach_dir)
          Dir.glob("#{attach_dir}/**/*") do |attach_path|
            if File.file?(attach_path)
              attach_file = attach_path[attach_dir.size + 1 .. -1]
              u8_attach_file = decode_filename(attach_file)
              dst_attach_path = File.expand_path("attach/#{u8_attach_file}",
                                                 dst_wiki_path)
              FileUtils.mkdir_p(File.dirname(dst_attach_path))
              FileUtils.cp(attach_path, dst_attach_path)
            end
          end
        end

        text_dir = "#{wiki_path}/text"
        if File.directory?(text_dir)
          Dir.glob("#{text_dir}/*") do |text_path|
            if File.file?(text_path)
              text_file = text_path[text_dir.size + 1 .. -1]
              u8_text_file = decode_filename(text_file)
              dst_text_path = File.expand_path("#{u8_text_file}.md",
                                               dst_wiki_path)
              p text_path
              text = File.read(text_path, encoding: "eucJP-ms").encode("utf-8")
              doc = HikiDocument.new(text)
              File.write(dst_text_path, doc.to_markdown)
            end
          end
        end
        
        #s = NKF.nkf("-w -m0", File.read(file))
        #doc = Hiki2md::HikiDocument.new(s)
        #print doc.to_markdown
      end
    end

    private

    def decode_filename(file)
      CGI.unescape(file).force_encoding("eucJP-ms").encode("utf-8").
        tr("/", "／")
    end
  end
end
