require "eventmachine"
require "websocket-eventmachine-client"
require "websocks/local/socks"
require "thread"

module Logger
  $stderr.sync = true

  LOCK = Mutex.new
  CONFIG = {cur_data: ""}

  def self.log(x)
    LOCK.synchronize do
      $stderr.write "\r" + " " * CONFIG[:cur_data].length + "\r"
      $stderr.puts x
      $stderr.write CONFIG[:cur_data]
    end
  end

  def self.update(x)
    LOCK.synchronize do
      $stderr.write "\r" + " " * CONFIG[:cur_data].length + "\r"
      CONFIG[:cur_data] = x
      $stderr.write CONFIG[:cur_data]
    end
  end
end

module Websocks::Local::Server
  class Slave
    def initialize(config)
      Logger.log "         Slave created"
      @on_connect = []
      @on_failure = []

      EM.next_tick do
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
          Logger.log "[  OK  ] Slave was connected"
          @slave.send config[:password], type: :text
        end

        @slave.onmessage do |msg, type|
          if type == :binary and msg.length > 0
            type = msg.each_byte.first
            payload = msg.byteslice(1..-1)

            if @slave.master
              if type == 1
                Logger.log "         Remote disconnected: #{@slave.master.addr}"
                @slave.master.close_connection_after_writing
                @slave.master = nil
                @connected = false
              else
                @slave.master.send_data payload
              end
            end
          elsif type == :text and not @slave.ok
            if msg == "OK"
              @slave.ok = true
              @slave.buffer.each do |m|
                @slave.send m, type: :binary
              end
              @slave.buffer = []
              @on_connect.each &:call
              @on_connect = []
            else
              @slave.close
              @on_failure.each { |p| p.call :auth }
              @on_failure = []
            end
          end
        end

        @slave.onclose do
          unless @slave.connected
            @on_failure.each &:call
            @on_failure = []
          end

          @slave.connected = false
          @slave.died = true

          Logger.log "[  ==  ] Slave connection closed"
        end

        if @on_established
          @on_established.call
          @on_established = nil
        end
      end
    end

    def on_connect(&blk)
      @on_connect.push blk
    end

    def on_failure(&blk)
      @on_failure.push blk
    end

    def connect(master, addr, port)
      @on_established = proc do
        @slave.master = master
        send_binary [port].pack("S>") + addr
        @slave.connected = true
      end
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
      @total = 0
    end

    def get_another
      @lock.synchronize do
        @pool.reject! &:died?

        if @pool.empty?
          res = Slave.new @config
          @total += 1
        else
          res = @pool.shift
        end

        log_current

        res
      end
    end

    def put_back(sl)
      @lock.synchronize do
        if sl.can_recycle?
          @pool.push(sl)
        elsif not sl.ok?
          sl.close
          @total -= 1
        end

        log_current
      end
    end

    def log_current
      Logger.update "         #{@pool.length} / #{@total} slaves queued"
    end
  end

  module Machine
    include Websocks::Local::Socks

    attr_accessor :buffer
    attr_accessor :slave_pool
    attr_accessor :addr

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
        address = req.address.serialize
        @addr = address
        Logger.log "         Connect: #{address}"
        begin
          @slave = @slave_pool.get_another
          @slave.connect self, address, req.port

          @slave.on_connect do
            send_obj Reply.new(
                reply: 0,
                addr_type: 1,
                address: Ipv4.new(x: [0, 0, 0, 0]),
                port: 1234
            )

            Logger.log "[  OK  ] Remote connected: #{address}"
          end

          @slave.on_failure do |reason = :failure|
            if reason == :auth
              Logger.log "[  !!  ] Incorrect password"
            end
            send_obj Reply.new reply: 5
            close_connection_after_writing
          end
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
      if @slave and @slave.ok? and @slave.connected?
        @slave.send_binary "\x01"
        @slave_pool.put_back @slave
      end
    end
  end
end
