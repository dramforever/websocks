require "eventmachine"

require "websocks/local/socks"

module Websocks::Local::Server
  module Machine
    include Websocks::Local::Socks

    def post_init
      @buffer = ""
      @waiting = Hello
      @next_call = :receive_hello
      @connection = nil
    end

    def send_obj(obj)
      send_data(obj.to_binary_s)
    end

    def receive_data data
      if @connection
        @connection.send_data data
      else
        @buffer << data

        begin
          x = @waiting.read(data)
          @buffer = @buffer.byteslice(x.num_bytes..-1)
          send @next_call, x
        rescue EOFError
          # Not enough data yet, wait for next time
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
        puts("Connection to %s" % addr)
        begin
          outer = self
          @connection = EM.connect addr, req.port do |c|
            c.instance_eval { @connection = outer }
            def c.post_init
            end

            def c.connection_completed
            end

            def c.receive_data(data)
              # I want this outer to refer to the object that
              # received the receive_request call
              @connection.send_data data
            end

            def c.unbind
              @connection.close_connection
            end
          end
        rescue
          p addr
          p $!
          send_obj Reply.new reply: 1
          close_connection_after_writing
          return
        end
        send_obj Reply.new(
            reply: 0,
            addr_type: 1,
            address: Ipv4.new(x: [0, 0, 0, 0]),
            port: 1234
        )
      else
        send_obj Reply.new reply: 7
        close_connection_after_writing
      end
    end

    def unbind
      if @connection
        @connection.close_connection
      end
    end
  end
end
