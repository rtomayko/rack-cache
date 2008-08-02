module Rack::Cache

  module Config

    # Evaluate a block of configuration code within the scope of
    # receiver.
    def configure(&block)
      instance_eval &block if block_given?
    end

    # Import the configuration file specified, evaluating its
    # contents within the scope of the receiver.
    def import(file)
      path = add_file_extension(file, 'rb')
      if path = locate_file_on_load_path(path)
        source = File.read(path)
        eval source, nil, path
        true
      else
        raise LoadError, 'no such file to load -- %s' % [file]
      end
    end

  private

    # Load the default configuration.
    def initialize_config(&b)
      import 'rack/cache/config/default'
      configure &b
    end

    # Attempt to expand +file+ to a full path by possibly adding an
    # .rb extension and traversing the $LOAD_PATH looking for matches.
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
