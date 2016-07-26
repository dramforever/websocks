require "eventmachine"
require "websocket-eventmachine-client"
require "websocks/local/socks"
require "thread"

module Websocks::Local::Server
  class Slave
    def initialize(config)
      @slave = WebSocket::EventMachine::Client.connect(
          uri: config[:uri],
          headers: {"X-Websocks" => "1"}
      )

      @slave.instance_eval do
        @master = nil
        @connected = false
        @died = false
        @ok = false
        @buffer = []
      end

      class << @slave
        attr_accessor :master
        attr_accessor :connected
        attr_accessor :died
        attr_accessor :ok
        attr_accessor :buffer
      end

      @slave.onopen do
        @slave.ok = true
        @slave.buffer.each do |msg|
          @slave.send msg, type: :binary
        end
        @slave.buffer = []
      end

      @slave.onmessage do |msg, type|
        if type == :binary and msg.length > 0
          type = msg.each_byte.first
          payload = msg.byteslice(1..-1)

          if @slave.master
            if type == 1
              @slave.master.close_connection_after_writing
              @slave.master = nil
              @connected = false
            else
              @slave.master.send_data payload
            end
          end
        end
      end

      @slave.onclose do
        @slave.connected = false
        @slave.died = true
      end
    end

    def connect(master, addr, port)
      @slave.master = master
      send_binary [port].pack("S>") + addr
      @slave.connected = true
    end

    def connected?
      @slave.connected
    end

    def can_recycle?
      not @slave.died
    end

    def send_binary(x)
      if ok?
        @slave.send x, type: :binary
      else
        @slave.buffer.push x
      end
    end

    def ok?
      @slave.ok
    end

    def died?
      @slave.died
    end
  end

  class SlavePool
    def initialize(config)
      @pool = []
      @config = config
      @lock = Mutex.new
    end

    def get_another
      @lock.synchronize do
        while not @pool.empty? and @pool[0].died?
          @pool.shift
        end
        if @pool.empty?
          Slave.new @config
        else
          @pool.shift
        end
      end
    end

    def put_back(sl)
      @lock.synchronize do
        if sl.can_recycle?
          @pool.push(sl)
        elsif not sl.ok?
          sl.close
        end
      end
    end
  end

  module Machine
    include Websocks::Local::Socks

    attr_accessor :buffer
    attr_accessor :config
    attr_accessor :slave_pool

    def post_init
      @buffer = ""
      @waiting = Hello
      @next_call = :receive_hello
      @slave = nil
    end

    def send_obj(obj)
      send_data(obj.to_binary_s)
    end


    def receive_data data
      if @slave
        @slave.send_binary "\x00" + data
      else
        @buffer << data

        begin
          x = @waiting.read(data)
          @buffer = @buffer.byteslice(x.num_bytes..-1)
          send @next_call, x
        rescue EOFError
          # Not enough data yet, wait for next time
        rescue
          close_connection
        end
      end
    end

    def receive_hello(hello)
      if hello.auth_methods.include? 0
        send_obj Auth.new auth_method: 0
        @waiting = Request
        @next_call = :receive_request
      else
        send_obj Auth.new auth_method: 0xff
        close_connection_after_writing
      end
    end

    def receive_request(req)
      if req.cmd == 1 # TCP Connect
        addr = req.address.serialize
        begin
          @slave = @slave_pool.get_another
          @slave.connect self, addr, req.port

          send_obj Reply.new(
              reply: 0,
              addr_type: 1,
              address: Ipv4.new(x: [0, 0, 0, 0]),
              port: 1234
          )
        rescue
          puts $!
          puts $!.backtrace
          send_obj Reply.new reply: 1
          close_connection_after_writing
        end
      else
        send_obj Reply.new reply: 7
        close_connection_after_writing
      end
    end

    def unbind
      if @slave and @slave.connected?
        @slave.send_binary "\x01" if @slave.ok?
        @slave_pool.put_back @slave
      end
    end
  end
end
