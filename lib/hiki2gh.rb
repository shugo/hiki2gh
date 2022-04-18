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
(?<plugin>\{\{.*?\}\})\
/
    
    def initialize(src, page_name = "")
      @src = src
      @page_name = page_name
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

    private

    def convert_inline(str)
      str.gsub(INILINE_RE) { |s|
        case
        when $~[:link]
          label, url = s.slice(/\[\[(.*?)\]\]/, 1).split(/\|/)
          case url
          when nil
            "[#{label}](#{label}.md)"
          when /\A:(.*)/
            u = attach_path($1.sub(/\A\.\.\//, ""))
            "[#{label}](#{u})"
          when /\Ahttps?:/
            "[#{label}](#{url})"
          else
            "[#{label}](#{url}.md)"
          end            
        when $~[:emphasis]
          s.gsub(/'''?/, "**")
        when $~[:strike]
          s.gsub(/==/, "~~")
        when $~[:plugin]
          case s
          when /\{\{attach_anchor\((.*?)\)?\}\}/
            path = attach_path($1)
            "[#{$1}](#{path})"
          when /\{\{attach_view\((.*?)\)?\}\}/
            path = attach_path($1)
            "![#{$1}](#{path})"
          else
            s
          end
        else
          s
        end
      }
    end

    def attach_path(file)
      "attach/#{@page_name}/#{file}"
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
              text = File.read(text_path, encoding: "eucJP-ms").encode("utf-8")
              page_name = File.basename(u8_text_file)
              doc = HikiDocument.new(text, page_name)
              File.write(dst_text_path, doc.to_markdown)
              if page_name == "FrontPage"
                FileUtils.cp(dst_text_path,
                             "#{dst_wiki_path}/README.md")
              end
            end
          end
        end
      end
    end

    private

    def decode_filename(file)
      file.gsub(/[^\/]+/) { |s|
        CGI.unescape(s).force_encoding("eucJP-ms").encode("utf-8").
          tr("/", "／")
      }
    end
  end
end

if $0 == __FILE__
  require "nkf"
  doc = Hiki2gh::HikiDocument.new(NKF.nkf("-w -m0", ARGF.read), "PageName")
  print doc.to_markdown
end
