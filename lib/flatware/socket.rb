require 'ffi-rzmq'

module Flatware
  Error = Class.new StandardError

  Job = Struct.new :id, :args do
    attr_accessor :worker
    attr_writer :failed

    def failed?
      !!@failed
    end
  end

  extend self

  def logger
    @logger ||= Logger.new($stderr)
  end

  def logger=(logger)
    @logger = logger
  end

  def socket(*args)
    context.socket(*args)
  end

  def close
    context.close
    @context = nil
  end

  def log(*message)
    if Exception === message.first
      logger.error message.first
    elsif verbose?
      logger.info ([$0] + message).join(' ')
    end
    message
  end

  attr_writer :verbose
  def verbose?
    !!@verbose
  end

  def context
    @context ||= Context.new
  end

  class Context
    attr_reader :sockets, :c

    def initialize
      @c = ZMQ::Context.new
      @sockets = []
    end

    def socket(type, options={})
      Socket.new(c.socket(type)).tap do |socket|
        sockets.push socket
        if port = options[:connect]
          socket.connect port
        end
        if port = options[:bind]
          socket.bind port
        end
      end
    end

    def close
      sockets.each &:close
      raise(Error, ZMQ::Util.error_string, caller) unless c.terminate == 0
      Flatware.log "terminated context"
    end
  end

  class Socket
    attr_reader :s
    def initialize(socket)
      @s = socket
    end

    def setsockopt(*args)
      s.setsockopt(*args)
    end

    def send(message)
      result = s.send_string(Marshal.dump(message))
      raise Error, ZMQ::Util.error_string, caller if result == -1
      Flatware.log "#@type #@port send #{message}"
      message
    end

    def connect(port)
      @type = 'connected'
      @port = port
      raise(Error, ZMQ::Util.error_string, caller) unless s.connect(port) == 0
      Flatware.log "connect #@port"
    end

    def bind(port)
      @type = 'bound'
      @port = port
      raise(Error, ZMQ::Util.error_string, caller) unless s.bind(port) == 0
      Flatware.log "bind #@port"
    end

    def close
      raise(Error, ZMQ::Util.error_string, caller) unless s.close == 0
      Flatware.log "close #@type #@port"
    end

    def recv(block=true)
      message = ''
      if block
       result = s.recv_string(message)
       raise Error, ZMQ::Util.error_string, caller if result == -1
      else
        s.recv_string(message, ZMQ::NOBLOCK)
      end
      message = Marshal.load(message) if message != ''
      Flatware.log "#@type #@port recv #{message}"
      message
    end
  end
end
