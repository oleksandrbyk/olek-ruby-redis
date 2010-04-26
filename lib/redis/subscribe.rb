class Redis
  class SubscribedClient
    def initialize(client)
      @client = client
    end

    def call(command, *args)
      @client.call_async(command, *args)
    end

    def subscribe(*channels, &block)
      @client.call_async(:subscribe, *channels)

      sub = Subscription.new(&block)

      begin
        loop do
          type, channel, message = @client.read
          sub.callbacks[type].call(channel, message)
          break if type == "unsubscribe" && message == 0
        end
      ensure
        @client.call_async(:unsubscribe)
      end
    end

    def unsubscribe(*channels)
      @client.call_async(:unsubscribe, *channels)
      @client
    end

    def psubscribe(*channels, &block)
      @client.call_async(:psubscribe, *channels)

      sub = Subscription.new(&block)

      begin
        loop do
          type, pattern, channel, message = @client.read
          sub.callbacks[type].call(pattern, channel, message)
          break if type == "punsubscribe" && channel == 0
        end
      ensure
        @client.call_async(:punsubscribe)
      end
    end

    def punsubscribe(*channels)
      @client.call_async(:punsubscribe, *channels)
      @client
    end
  end

  class Subscription
    attr :callbacks

    def initialize
      @callbacks = Hash.new do |hash, key|
        hash[key] = lambda { |*_| }
      end

      yield(self)
    end

    def subscribe(&block)
      @callbacks["subscribe"] = block
    end

    def unsubscribe(&block)
      @callbacks["unsubscribe"] = block
    end

    def message(&block)
      @callbacks["message"] = block
    end

    def psubscribe(&block)
      @callbacks["psubscribe"] = block
    end

    def punsubscribe(&block)
      @callbacks["punsubscribe"] = block
    end

    def pmessage(&block)
      @callbacks["pmessage"] = block
    end
  end
end
