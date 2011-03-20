require "em-synchrony"
require "hiredis/reader"

class Redis
  module Connection
    class RedisClient < EventMachine::Connection
      include EventMachine::Deferrable

      def post_init
        @req = nil
        @reader = ::Hiredis::Reader.new
      end

      def connection_completed
        succeed
      end

      def receive_data(data)
        @reader.feed(data)
        until (reply = @reader.gets) == false
          @req.succeed reply
        end
      end

      def read
        @req = EventMachine::DefaultDeferrable.new
        EventMachine::Synchrony.sync @req
      end

      def send(data)
        callback { send_data data }
      end

      def unbind
        if @req
          @req.fail
          @req = nil
        else
          fail
        end
      end
    end

    class Synchrony
      include Redis::Connection::CommandHelper

      def initialize
        @timeout = 5_000_000
        @state = :disconnected
        @connection = nil
      end

      def connected?
        @state == :connected
      end

      def timeout=(usecs)
        @timeout = usecs
      end

      def connect(host, port, timeout)
        conn = EventMachine.connect(host, port, RedisClient) do |c|
          c.pending_connect_timeout = [Float(timeout / 1_000_000), 0.1].max
        end

        setup_connect_callbacks(conn, Fiber.current)
      end

      def connect_unix(path, timeout)
        conn = EventMachine.connect_unix_domain(path, RedisClient)
        setup_connect_callbacks(conn, Fiber.current)
      end

      def disconnect
        @state = :disconnected
        @connection.close_connection
        @connection = nil
      end

      def write(command)
        @connection.send(build_command(*command).join(COMMAND_DELIMITER))
      end

      def read
        @connection.read
      rescue RuntimeError => err
        raise ::Redis::ProtocolError.new(err.message)
      end

      private

        def setup_connect_callbacks(conn, f)
          conn.callback do
            @connection = conn
            @state = :connected
            f.resume conn
          end

          conn.errback do
            @connection = conn
            f.resume :refused
          end

          r = Fiber.yield
          raise Errno::ECONNREFUSED if r == :refused
          r
        end

    end
  end
end
