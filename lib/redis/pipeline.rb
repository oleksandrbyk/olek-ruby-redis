class Redis
  class Pipeline
    attr :futures

    def initialize
      @without_reconnect = false
      @shutdown = false
      @futures = []
    end

    def without_reconnect?
      @without_reconnect
    end

    def shutdown?
      @shutdown
    end

    def call(command, &block)
      # A pipeline that contains a shutdown should not raise ECONNRESET when
      # the connection is gone.
      @shutdown = true if command.first == :shutdown
      future = Future.new(command, block)
      @futures << future
      future
    end

    def call_pipeline(pipeline)
      @shutdown = true if pipeline.shutdown?
      @futures.concat(pipeline.futures)
      nil
    end

    def commands
      @futures.map { |f| f._command }
    end

    def without_reconnect(&block)
      @without_reconnect = true
      yield
    end

    def process_replies(replies)
      futures.each_with_index.map do |future, i|
        future._set(replies[i])
      end
    end
  end

  class FutureNotReady < RuntimeError
    def initialize
      super("Value will be available once the pipeline executes.")
    end
  end

  class Future < BasicObject
    FutureNotReady = ::Redis::FutureNotReady.new

    def initialize(command, transformation)
      @command = command
      @transformation = transformation
      @object = FutureNotReady
    end

    def inspect
      "<Redis::Future #{@command.inspect}>"
    end

    def _set(object)
      @object = @transformation ? @transformation.call(object) : object
      value
    end

    def _command
      @command
    end

    def value
      ::Kernel.raise(@object) if @object.kind_of?(::Exception)
      @object
    end
  end
end
