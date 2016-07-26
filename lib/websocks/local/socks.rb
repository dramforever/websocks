require "bindata"

module Websocks
  module Local
    module Socks
      class Hello < BinData::Record
        endian :big

        uint8 :ver,
              initial_value: 5,
              assert: lambda { ver == 5 }

        uint8 :len, initial_value: 1, assert: lambda { len > 0 }

        array :auth_methods,
              type: :uint8,
              initial_length: :len,
              initial_value: [0]
      end

      class Auth < BinData::Record
        endian :big

        uint8 :ver, value: 5
        uint8 :auth_method
      end

      class Ipv4 < BinData::Record
        endian :big

        array :x,
              type: :uint8,
              initial_length: 4

        def serialize
          x.to_a.join "."
        end
      end

      class Ipv6 < BinData::Record
        endian :big

        array :x,
              type: :uint16,
              initial_length: 8

        def serialize
          x.to_a.join ":"
        end
      end

      class DomainName < BinData::Record
        endian :big

        uint8 :len
        string :x, length: :len

        def serialize
          x
        end
      end

      class Request < BinData::Record
        endian :big

        uint8 :ver,
              initial_value: 5,
              assert: lambda { ver == 5 }

        uint8 :cmd,
              assert: lambda { cmd == 0 or cmd == 1 or cmd == 2 }

        skip length: 1 # RESERVED

        uint8 :addr_type,
              assert: (lambda do
                addr_type == 1 or
                    addr_type == 3 or
                    addr_type == 4
              end)

        choice :address,
               selection: :addr_type,
               choices: {
                   1 => :ipv4,
                   3 => :domain_name,
                   4 => :ipv6
               }

        uint16 :port
      end

      class Reply < BinData::Record
        endian :big

        uint8 :ver,
              initial_value: 5,
              assert: lambda { ver == 5 }

        uint8 :reply

        skip length: 1 # RESERVED

        uint8 :addr_type,
              assert: (lambda do
                addr_type == 1 or
                    addr_type == 3 or
                    addr_type == 4
              end),
              initial_value: 1

        choice :address,
               selection: :addr_type,
               choices: {
                   1 => :ipv4,
                   3 => :domain_name,
                   4 => :ipv6
               }

        uint16 :port
      end
    end
  end
end