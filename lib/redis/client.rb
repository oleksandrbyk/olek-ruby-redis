class Redis
  class Client
    OK      = "OK".freeze
    MINUS    = "-".freeze
    PLUS     = "+".freeze
    COLON    = ":".freeze
    DOLLAR   = "$".freeze
    ASTERISK = "*".freeze

    BULK_COMMANDS = {
      "set"       => true,
      "setnx"     => true,
      "rpush"     => true,
      "lpush"     => true,
      "lset"      => true,
      "lrem"      => true,
      "sadd"      => true,
      "srem"      => true,
      "sismember" => true,
      "echo"      => true,
      "getset"    => true,
      "smove"     => true,
      "zadd"      => true,
      "zincrby"   => true,
      "zrem"      => true,
      "zscore"    => true,
      "zrank"     => true,
      "zrevrank"  => true,
      "hget"      => true,
      "hdel"      => true,
      "hexists"   => true,
      "publish"   => true
    }

    MULTI_BULK_COMMANDS = {
      "mset"      => true,
      "msetnx"    => true,
      "hset"      => true
    }

    BOOLEAN_PROCESSOR = lambda{|r| r == 1 }

    REPLY_PROCESSOR = {
      "exists"    => BOOLEAN_PROCESSOR,
      "sismember" => BOOLEAN_PROCESSOR,
      "sadd"      => BOOLEAN_PROCESSOR,
      "srem"      => BOOLEAN_PROCESSOR,
      "smove"     => BOOLEAN_PROCESSOR,
      "zadd"      => BOOLEAN_PROCESSOR,
      "zrem"      => BOOLEAN_PROCESSOR,
      "move"      => BOOLEAN_PROCESSOR,
      "setnx"     => BOOLEAN_PROCESSOR,
      "del"       => BOOLEAN_PROCESSOR,
      "renamenx"  => BOOLEAN_PROCESSOR,
      "expire"    => BOOLEAN_PROCESSOR,
      "hset"      => BOOLEAN_PROCESSOR,
      "hexists"   => BOOLEAN_PROCESSOR,
      "info"      => lambda{|r|
        info = {}
        r.each_line {|kv|
          k,v = kv.split(":",2).map{|x| x.chomp}
          info[k.to_sym] = v
        }
        info
      },
      "keys"      => lambda{|r|
        if r.is_a?(Array)
            r
        else
            r.split(" ")
        end
      },
      "hgetall"   => lambda{|r|
        Hash[*r]
      }
    }

    ALIASES = {
      "flush_db"             => "flushdb",
      "flush_all"            => "flushall",
      "last_save"            => "lastsave",
      "key?"                 => "exists",
      "delete"               => "del",
      "randkey"              => "randomkey",
      "list_length"          => "llen",
      "push_tail"            => "rpush",
      "push_head"            => "lpush",
      "pop_tail"             => "rpop",
      "pop_head"             => "lpop",
      "list_set"             => "lset",
      "list_range"           => "lrange",
      "list_trim"            => "ltrim",
      "list_index"           => "lindex",
      "list_rm"              => "lrem",
      "set_add"              => "sadd",
      "set_delete"           => "srem",
      "set_count"            => "scard",
      "set_member?"          => "sismember",
      "set_members"          => "smembers",
      "set_intersect"        => "sinter",
      "set_intersect_store"  => "sinterstore",
      "set_inter_store"      => "sinterstore",
      "set_union"            => "sunion",
      "set_union_store"      => "sunionstore",
      "set_diff"             => "sdiff",
      "set_diff_store"       => "sdiffstore",
      "set_move"             => "smove",
      "set_unless_exists"    => "setnx",
      "rename_unless_exists" => "renamenx",
      "type?"                => "type",
      "zset_add"             => "zadd",
      "zset_count"           => "zcard",
      "zset_range_by_score"  => "zrangebyscore",
      "zset_reverse_range"   => "zrevrange",
      "zset_range"           => "zrange",
      "zset_delete"          => "zrem",
      "zset_score"           => "zscore",
      "zset_incr_by"         => "zincrby",
      "zset_increment_by"    => "zincrby"
    }

    DISABLED_COMMANDS = {
      "monitor" => true,
      "sync"    => true
    }

    def initialize(options = {})
      @host    =  options[:host]    || '127.0.0.1'
      @port    = (options[:port]    || 6379).to_i
      @db      = (options[:db]      || 0).to_i
      @timeout = (options[:timeout] || 5).to_i
      @password = options[:password]
      @logger  =  options[:logger]
      @thread_safe = options[:thread_safe]
      @binary_keys = options[:binary_keys]
      @mutex = Mutex.new if @thread_safe
      @sock = nil
      @pubsub = false

      log(self)
    end

    def to_s
      "Redis Client connected to #{server} against DB #{@db}"
    end

    def select(*args)
      raise "SELECT not allowed, use the :db option when creating the object"
    end

    def [](key)
      self.get(key)
    end

    def []=(key,value)
      set(key,value)
    end

    def set(key, value, expiry=nil)
      reply = call_command([:set, key, value])
      expire(key, expiry) if reply == OK and expiry
      reply
    end

    def mset(*args)
      hsh = args.pop if Hash === args.last
      if hsh
        call_command(hsh.to_a.flatten.unshift(:mset))
      else
        call_command(args.unshift(:mset))
      end
    end

    def msetnx(*args)
      hsh = args.pop if Hash === args.last
      if hsh
        call_command(hsh.to_a.flatten.unshift(:msetnx))
      else
        call_command(args.unshift(:msetnx))
      end
    end

    def sort(key, options = {})
      cmd = ["SORT"]
      cmd << key
      cmd << "BY #{options[:by]}" if options[:by]
      cmd << "GET #{[options[:get]].flatten * ' GET '}" if options[:get]
      cmd << "#{options[:order]}" if options[:order]
      cmd << "LIMIT #{options[:limit].join(' ')}" if options[:limit]
      cmd << "STORE #{options[:store]}" if options[:store]
      call_command(cmd)
    end

    def incr(key, increment = nil)
      call_command(increment ? ["incrby",key,increment] : ["incr",key])
    end

    def decr(key,decrement = nil)
      call_command(decrement ? ["decrby",key,decrement] : ["decr",key])
    end

    # Similar to memcache.rb's #get_multi, returns a hash mapping
    # keys to values.
    def mapped_mget(*keys)
      result = {}
      mget(*keys).each do |value|
        key = keys.shift
        result.merge!(key => value) unless value.nil?
      end
      result
    end

    # Ruby defines a now deprecated type method so we need to override it here
    # since it will never hit method_missing
    def type(key)
      call_command(['type', key])
    end

    def quit
      call_command(['quit'])
    rescue Errno::ECONNRESET
    end

    def pipelined(&block)
      pipeline = Pipeline.new self
      yield pipeline
      pipeline.execute
    end

    def exec
      # Need to override Kernel#exec.
      call_command([:exec])
    end

    def multi(&block)
      result = call_command [:multi]

      return result unless block_given?

      begin
        yield(self)
        exec
      rescue Exception => e
        discard
        raise e
      end
    end

    def subscribe(*classes)
        # Sanity check, as our API is a bit tricky. You MUST call
        # the top-level subscribe with a block, but you can NOT call
        # the nested subscribe calls with a block, as all the messages
        # are processed by the top level call.
        if @pubsub == false and !block_given?
            raise "You must pass a block to the top level subscribe call"
        elsif @pubsub == true and block_given?
            raise "Can't pass a block to nested subscribe calls"
        elsif @pubsub == true
            # This is a nested subscribe call without a block given.
            # We just need to send the subscribe command and return asap.
            call_command [:subscribe,*classes]
            return true
        end
        @pubsub = true
        call_command [:subscribe,*classes]
        while true
            r = read_reply
            msg = {:type => r[0], :class => r[1], :data => r[2]}
            yield(msg)
            break if msg[:type] == "unsubscribe" and r[2] == 0
        end
        @pubsub = false
    end

    def unsubscribe(*classes)
        call_command [:unsubscribe,*classes]
        return true
    end

  protected

    def call_command(argv)
      log(argv.inspect, :debug)

      # this wrapper to raw_call_command handle reconnection on socket
      # error. We try to reconnect just one time, otherwise let the error
      # araise.
      connect_to_server if !@sock

      begin
        raw_call_command(argv.dup)
      rescue Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNABORTED
        @sock.close rescue nil
        @sock = nil
        connect_to_server
        raw_call_command(argv.dup)
      end
    end

  private

    def server
      "#{@host}:#{@port}"
    end

    def connect_to(host, port, timeout=nil)
      # We support connect() timeout only if system_timer is availabe
      # or if we are running against Ruby >= 1.9
      # Timeout reading from the socket instead will be supported anyway.
      if @timeout != 0 and Timer
        begin
          sock = TCPSocket.new(host, port)
        rescue Timeout::Error
          @sock = nil
          raise Timeout::Error, "Timeout connecting to the server"
        end
      else
        sock = TCPSocket.new(host, port)
      end
      sock.setsockopt Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1

      # If the timeout is set we set the low level socket options in order
      # to make sure a blocking read will return after the specified number
      # of seconds. This hack is from memcached ruby client.
      if timeout
        secs   = Integer(timeout)
        usecs  = Integer((timeout - secs) * 1_000_000)
        optval = [secs, usecs].pack("l_2")
        begin
          sock.setsockopt Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, optval
          sock.setsockopt Socket::SOL_SOCKET, Socket::SO_SNDTIMEO, optval
        rescue Exception => ex
          # Solaris, for one, does not like/support socket timeouts.
          log("Unable to use raw socket timeouts: #{ex.class.name}: #{ex.message}")
        end
      end
      sock
    end

    def connect_to_server
      @sock = connect_to(@host, @port, @timeout == 0 ? nil : @timeout)
      call_command(["auth",@password]) if @password
      call_command(["select",@db]) unless @db == 0
    end

    def method_missing(*argv)
      call_command(argv)
    end

    def raw_call_command(argvp)
      if argvp[0].is_a?(Array)
        argvv = argvp
        pipeline = true
      else
        argvv = [argvp]
      end

      if @binary_keys or MULTI_BULK_COMMANDS[argvv[0][0].to_s]
        command = ""
        argvv.each do |argv|
          command << "*#{argv.size}\r\n"
          argv.each{|a|
            a = a.to_s
            command << "$#{get_size(a)}\r\n"
            command << a
            command << "\r\n"
          }
        end
      else
        command = ""
        argvv.each do |argv|
          bulk = nil
          argv[0] = argv[0].to_s
          if ALIASES[argv[0]]
            $stderr.puts "\nredis: The method #{argv[0]} is deprecated. Use #{ALIASES[argv[0]]} instead (in #{caller[4]})"
            argv[0] = ALIASES[argv[0]]
          end
          raise "#{argv[0]} command is disabled" if DISABLED_COMMANDS[argv[0]]
          if BULK_COMMANDS[argv[0]] and argv.length > 1
            bulk = argv[-1].to_s
            argv[-1] = get_size(bulk)
          end
          command << "#{argv.join(' ')}\r\n"
          command << "#{bulk}\r\n" if bulk
        end
      end
      # When in Pub/Sub mode we don't read replies synchronously.
      if @pubsub
        @sock.write(command)
        return true
      end
      # The normal command execution is reading and processing the reply.
      results = maybe_lock { process_command(command, argvv) }
      return pipeline ? results : results[0]
    end

    def process_command(command, argvv)
      @sock.write(command)
      argvv.map do |argv|
        processor = REPLY_PROCESSOR[argv[0].to_s]
        processor ? processor.call(read_reply) : read_reply
      end
    end

    def maybe_lock(&block)
      if @thread_safe
        @mutex.synchronize(&block)
      else
        block.call
      end
    end

    def read_reply
      # We read the first byte using read() mainly because gets() is
      # immune to raw socket timeouts.
      begin
        rtype = @sock.read(1)
      rescue Errno::EAGAIN
        # We want to make sure it reconnects on the next command after the
        # timeout. Otherwise the server may reply in the meantime leaving
        # the protocol in a desync status.
        @sock = nil
        raise Errno::EAGAIN, "Timeout reading from the socket"
      end

      raise Errno::ECONNRESET,"Connection lost" if !rtype
      line = @sock.gets
      case rtype
      when MINUS
        raise MINUS + line.strip
      when PLUS
        line.strip
      when COLON
        line.to_i
      when DOLLAR
        bulklen = line.to_i
        return nil if bulklen == -1
        data = @sock.read(bulklen)
        @sock.read(2) # CRLF
        data
      when ASTERISK
        objects = line.to_i
        return nil if bulklen == -1
        res = []
        objects.times {
          res << read_reply
        }
        res
      else
        raise "Protocol error, got '#{rtype}' as initial reply byte"
      end
    end

    def get_size(string)
      string.respond_to?(:bytesize) ? string.bytesize : string.size
    end

    def log(str, level = :info)
      @logger.send(level, str.to_s) if @logger
    end
  end
end
