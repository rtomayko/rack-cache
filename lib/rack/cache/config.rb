module Rack::Cache

  module Config

    attr_reader :events

    attr_reader :trace

    def initialize_config
      @events = Hash.new { |h,k| h[k.to_sym] = [] }
      @trace = []
    end

    protected :initialize_config

    # Import the configuration file specified.
    def import(file)
      path = add_file_extension(file, 'rb')
      if path = locate_file_on_load_path(path)
        source = File.read(path)
        eval source, nil, file
        true
      else
        raise LoadError, 'no such file to load -- %s' % [file]
      end
    end

  private

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

  public

    # Attach rules to an event.
    def on(event, &block)
      @events[event].unshift block
      nil
    end

    # Bootstrap or transition the machine to the event specified.
    def perform(event)
      if @trace.any?
        transition(event)
      else
        bootstrap(event)
      end
    end

    # Has the event been performed at any time during the request
    # life-cycle? Most useful for testing.
    def performed?(event)
      @trace.include?(event)
    end

    # Are we currently performing the event specified?
    def performing?(event)
      @trace.last == event
    end

  private

    # Bootstrap the configuration machine at the event specified.
    def bootstrap(event)
      while event
        if (events = @events[event]).any?
          @trace << event
          event =
            catch(:transition) do
              events.each { |block| instance_eval(&block) }
              nil
            end
        else
          fail "NoEvent: #{event}"
        end
      end
    end

    # Transition from the currently processing event to the event
    # specified.
    def transition(event)
      throw :transition, event.to_sym
    end

  public

    # We respond to messages with event names (performs the event).
    def respond_to?(symbol, include_private=false)
      @events.key?(symbol) || super
    end

  private

    # Perform events when messages are received that match event names.
    def method_missing(symbol, *args, &b)
      if args.empty? && b.nil? && @events.key?(symbol)
        perform symbol
      else
        super
      end
    end

  end

end
