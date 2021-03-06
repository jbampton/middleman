# frozen_string_literal: true

# Core Pathname library used for traversal
require 'pathname'

# DbC
require 'middleman-core/contracts'

require 'middleman-core/util/data'

# Extensions namespace
module Middleman::CoreExtensions
  class FrontMatter < ::Middleman::Extension
    # Try to run after routing but before directory_indexes
    self.resource_list_manipulator_priority = 20

    # Set textual delimiters that denote the start and end of frontmatter
    define_setting :frontmatter_delims, {
      json: [%w[;;; ;;;]],
      yaml: [
        # Normal
        %w[--- ---],

        # Pandoc
        %w[--- ...],

        # Haml with commented frontmatter
        ["-#\n  ---", '  ---'],

        # Slim with commented frontmatter
        ["\/\n  ---", '  ---'],

        # ERb with commented frontmatter
        ["<%#\n  ---", "  ---\n%>"]
      ]
    }, 'Allowed frontmatter delimiters'

    def initialize(app, options_hash = ::Middleman::EMPTY_HASH, &block)
      super

      @cache = {}
    end

    def before_configuration
      app.files.on_change(:source, &method(:clear_data))
    end

    Contract IsA['Middleman::Sitemap::ResourceListContainer'] => Any
    def manipulate_resource_list_container!(resource_list)
      resource_list.by_binary(false).each do |resource|
        next if resource.file_descriptor.nil?
        next if resource.file_descriptor[:types].include?(:no_frontmatter)

        fmdata = data(resource.file_descriptor[:full_path].to_s).first.dup

        # Copy over special options
        # TODO: Should we make people put these under "options" instead of having
        # special known keys?
        opts = fmdata.extract!(:layout, :layout_engine, :renderer_options, :directory_index, :content_type)
        opts[:renderer_options].symbolize_keys! if opts.key?(:renderer_options)

        ignored = fmdata.delete(:ignored)

        # TODO: Enhance data? NOOOO
        # TODO: stringify-keys? immutable/freeze?

        resource.add_metadata_options opts

        if fmdata.key?(:id)
          resource_list.update!(resource, :page_id) do
            resource.add_metadata_page fmdata
          end
        else
          resource.add_metadata_page fmdata
        end

        next unless ignored == true && !resource.is_a?(::Middleman::Sitemap::ProxyResource)

        resource_list.update!(resource, :ignored) do
          resource.ignore!
        end

        # TODO: Save new template here somewhere?
      end
    end

    # Get the template data from a path
    # @param [String] path
    # @return [String]
    Contract String => Maybe[String]
    def template_data_for_file(path)
      data(path).last
    end

    Contract String => [Hash, Maybe[String]]
    def data(path)
      file = app.files.find(:source, path)

      return [{}, nil] unless file

      file_path = file[:full_path].to_s

      @cache[file_path] ||= begin
        if ::Middleman::Util.contains_frontmatter?(file_path, app.config[:frontmatter_delims])
          ::Middleman::Util::Data.parse(
            file,
            app.config[:frontmatter_delims]
          )
        else
          [{}, nil]
        end
      end
    end

    Contract ArrayOf[IsA['Middleman::SourceFile']], ArrayOf[IsA['Middleman::SourceFile']] => Any
    def clear_data(updated_files, removed_files)
      (updated_files + removed_files).each do |file|
        @cache.delete(file[:full_path].to_s)
      end
    end
  end
end
