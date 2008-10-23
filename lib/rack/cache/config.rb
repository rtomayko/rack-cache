require 'set'

module Rack::Cache
  # Provides cache configuration methods. This module is included in the cache
  # context object.

  module Config
    # Evaluate a block of configuration code within the scope of receiver.
    def configure(&block)
      instance_eval(&block) if block_given?
    end

    # Import the configuration file specified. This has the same basic semantics
    # as Ruby's built-in +require+ statement but always evaluates the source
    # file within the scope of the receiver. The file may exist anywhere on the
    # $LOAD_PATH.
    def import(file)
      return false if imported_features.include?(file)
      path = add_file_extension(file, 'rb')
      if path = locate_file_on_load_path(path)
        source = File.read(path)
        imported_features.add(file)
        instance_eval source, path, 1
        true
      else
        raise LoadError, 'no such file to load -- %s' % [file]
      end
    end

  private
    # Load the default configuration and evaluate the block provided within
    # the scope of the receiver.
    def initialize_config(&block)
      import 'rack/cache/config/default'
      configure(&block)
    end

    # Set of files that have been imported.
    def imported_features
      @imported_features ||= Set.new
    end

    # Attempt to expand +file+ to a full path by possibly adding an .rb
    # extension and traversing the $LOAD_PATH looking for matches.
    def locate_file_on_load_path(file)
      if file[0,1] == '/'
        file if File.exist?(file)
      else
        $LOAD_PATH.
          map { |base| File.join(base, file) }.
          detect { |p| File.exist?(p) }
      end
    end

    # Add an extension to the filename provided if the file doesn't
    # already have extension.
    def add_file_extension(file, extension='rb')
      if file =~ /\.\w+$/
        file
      else
        "#{file}.#{extension}"
      end
    end
  end
end
