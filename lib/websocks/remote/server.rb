require "em-websocket"

module Websocks
  module Remote
    def self.run(config)
      EM::WebSocket.run(
          host: "0.0.0.0",
          port: config[:port]
      ) do |ws|
        class << ws
          attr_accessor :external
          attr_accessor :buffer
          attr_accessor :connected
        end

        ws.instance_eval do
          @external = nil
          @buffer = []
          @connected = false
        end

        ws.onmessage do |msg|
          if msg == config[:password]
            ws.send_text "OK"
            ws.connected = true
            ws.buffer.each { |m| ws.send_binary m }
          else
            ws.send_text "BAD"
            ws.close
          end
        end

        ws.onbinary do |msg|
          if ws.external
            if msg.length > 0
              type = msg.each_byte.first
              payload = msg.byteslice(1..-1)
              if type == 1
                ws.external.close_connection_after_writing
                ws.external = nil
              else
                if ws.external.connected
                  ws.external.send_data payload
                else
                  ws.external.buffer << payload
                end
              end
            end
          else
            if msg.length > 2
              addr = msg.byteslice(2..-1)
              port = msg.unpack("S>")[0]
              begin
                ws.external = EM.connect addr, port do |c|
                  c.instance_eval do
                    @slave = ws
                    @connected = false
                    @buffer = ""
                  end

                  class << c
                    attr_accessor :connected
                    attr_accessor :buffer
                  end

                  def c.connection_completed
                    @connected = true
                    send_data @buffer
                    @slave.buffer = ""
                  end

                  def c.receive_data(data)
                    @slave.send_binary("\x00" + data)
                  end

                  def c.unbind
                    @slave.send_binary("\x01")
                  end
                end
              rescue
                $stderr.puts $!
                $stderr.puts $!.backtrace
                ws.send_data("\x01")
              end
            end
          end
        end

        ws.onclose do
          @external.close rescue nil
        end
      end
    end
  end
end