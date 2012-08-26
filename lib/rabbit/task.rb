# Copyright (C) 2012 Kouhei Sutou <kou@cozmixng.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

require "rake"

require "rabbit/gettext"
require "rabbit/logger"
require "rabbit/command/rabbit"

module Rabbit
  module Task
    class Slide
      include Rake::DSL
      include GetText

      attr_reader :spec
      attr_accessor :package_dir, :pdf_dir, :pdf_base_path
      attr_accessor :tags
      attr_accessor :rubygems_user, :slideshare_user, :speaker_deck_user
      def initialize(spec)
        @logger = Logger.default
        @spec = spec
        @package_dir = "pkg"
        @pdf_dir = "pdf"
        @pdf_base_path = nil
        @tags = []
        @rubygems_user = nil
        @slideshare_user = nil
        @speaker_deck_user = nil
        yield(self) if block_given?
        define
      end

      private
      def define
        task :default => :run

        options_file = ".rabbit"
        file options_file do
          format = _("To run rabbit, create '%{options_file}'!")
          raise(format % {:options_file => options_file})
        end

        desc(_("Show slide"))
        task :run => options_file do
          rabbit
        end

        desc(_("Create gem: %{gem_path}") % {:gem_path => gem_path})
        task :gem => "gem:validate" do
          mkdir_p(@package_dir)
          Gem::Builder.new(@spec).build
          mv(File.basename(@spec.cache_file), gem_path)
        end

        namespace :gem do
          task :validate do
            errors = []
            format = _("Write %{item} in %{where}: %{content}")
            data = {
              :where => Dir.glob("README*")[0],
            }
            [:summary, :description].each do |item|
              content = @spec.send(item)
              if /TODO|FIXME/ =~ content
                data[:item] = item
                data[:content] = content
                errors << (format % data)
              end
            end
            unless errors.empty?
              raise errors.join("\n")
            end
          end
        end

        pdf_path = File.join(@pdf_dir, @pdf_base_path || default_pdf_base_path)
        file pdf_path => [options_file, *@spec.files] do
          mkdir_p(@pdf_dir)
          rabbit("--print",
                 "--output-filename", pdf_path)
        end

        desc(_("Generate PDF: %{pdf_path}") % {:pdf_path => pdf_path})
        task :pdf => pdf_path

        desc(_("Publish the slide to all available targets"))
        task :publish

        publish_tasks = []
        namespace :publish do
          if @rubygems_user
            desc(_("Publish the slide to RubyGems.org"))
            task :rubygems => :gem do
              ruby("-S", "gem", "push", "--verbose", gem_path)
            end
            publish_tasks << :rubygems
          end

          if @slideshare_user
            desc(_("Publish the slide to SlideShare"))
            task :slideshare => [:pdf, "gem:validate"] do
              require "rabbit/slideshare"
              slideshare = SlideShare.new(@logger)
              slideshare.user = @slideshare_user
              slideshare.pdf_path = pdf_path
              slideshare.title = @spec.summary
              slideshare.description = @spec.description
              slideshare.tags = @tags if @tags
              id = slideshare.upload
              if id
                url = "http://www.slideshare.net/#{@slideshare_user}/ss-#{id}"
                @logger.info(_("Uploaded successfully!"))
                @logger.info(_("See %s") % url)
                Gtk.show_uri(url) if Gtk.respond_to?(:show_uri)
              end
            end
            publish_tasks << :slideshare
          end

          if @speaker_deck_user
            desc(_("Publish the slide to Spearker Deck"))
            task :speaker_deck => :pdf do
              raise "Not implemented yet."
            end
            publish_tasks << :speaker_deck
          end
        end
        task :publish => publish_tasks.collect {|task| "publish:#{task}"}
      end

      def gem_path
        File.join(@package_dir, "#{@spec.name}-#{@spec.version}.gem")
      end

      def default_pdf_base_path
        user_name_and_slide_id = @spec.name.gsub(/\Arabbit-slide-/, "")
        escaped_user = Regexp.escape(@rubygems_user)
        slide_id = user_name_and_slide_id.gsub(/\A#{escaped_user}-/, "")
        "#{slide_id}.pdf"
      end

      def rabbit(*arguments)
        Rabbit::Command::Rabbit.run(*arguments)
      end
    end
  end
end